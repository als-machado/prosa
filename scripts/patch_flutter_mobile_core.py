"""
Patcha Flutter.framework/Flutter para tornar weak links os frameworks
depreciados/removidos no iOS 26 que ainda estão como LC_LOAD_DYLIB (hard).

Frameworks-alvo:
  - MobileCoreServices: depreciado iOS 14, removido iOS 26
  - OpenGLES: depreciado iOS 12, removido iOS 26

Com LC_LOAD_WEAK_DYLIB em vez de LC_LOAD_DYLIB, o dyld ignora a ausência
do framework em vez de matar o processo com POSIX error 85.
"""
import struct, sys

path = sys.argv[1]

LC_LOAD_DYLIB      = 0x0000000C
LC_LOAD_WEAK_DYLIB = 0x80000018

# Fragmentos de nome (bytes) que identificam cada framework depreciado/removido.
# CoreServices e MobileCoreServices são o mesmo ecossistema (UTType, etc.) e
# foram depreciados juntos em favor de UniformTypeIdentifiers no iOS 14+.
TARGETS = [
    b'MobileCoreServices',
    b'CoreServices',
]

def patch_arch(data, offset):
    magic = struct.unpack_from('<I', data, offset)[0]
    if magic != 0xFEEDFACF:
        return False
    ncmds = struct.unpack_from('<I', data, offset + 16)[0]
    pos = offset + 32  # sizeof(mach_header_64)
    found = False
    for _ in range(ncmds):
        cmd     = struct.unpack_from('<I', data, pos)[0]
        cmdsize = struct.unpack_from('<I', data, pos + 4)[0]
        if cmdsize <= 0:
            break
        if cmd == LC_LOAD_DYLIB:
            name_off = struct.unpack_from('<I', data, pos + 8)[0]
            name_bytes = data[pos + name_off : pos + name_off + 80]
            for target in TARGETS:
                if target in name_bytes:
                    name_str = name_bytes.split(b'\x00')[0].decode('utf-8', errors='replace')
                    print(f'  → Patch: LC_LOAD_DYLIB @ offset {pos} ({name_str}) → LC_LOAD_WEAK_DYLIB')
                    struct.pack_into('<I', data, pos, LC_LOAD_WEAK_DYLIB)
                    found = True
                    break
        pos += cmdsize
    return found

with open(path, 'rb') as f:
    data = bytearray(f.read())

magic_be = struct.unpack_from('>I', data, 0)[0]
patched = False

if magic_be == 0xCAFEBABE:  # FAT binary
    nfat = struct.unpack_from('>I', data, 4)[0]
    print(f'FAT binary com {nfat} arch(s)')
    for i in range(nfat):
        off = struct.unpack_from('>I', data, 8 + i * 20)[0]
        patched |= patch_arch(data, off)
else:
    patched = patch_arch(data, 0)

if patched:
    with open(path, 'wb') as f:
        f.write(data)
    print('Patch aplicado com sucesso.')
else:
    print('Nenhum target encontrado (já são weak ou não estão presentes).')
sys.exit(0)
