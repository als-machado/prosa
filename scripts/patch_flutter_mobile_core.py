"""
Patcha Flutter.framework/Flutter para tornar MobileCoreServices um weak link.
MobileCoreServices foi depreciado no iOS 14 e possivelmente removido no iOS 26.
Com LC_LOAD_WEAK_DYLIB em vez de LC_LOAD_DYLIB, o dyld não mata o processo
caso o framework não exista no dispositivo.
"""
import struct, sys

path = sys.argv[1]

LC_LOAD_DYLIB      = 0x0000000C
LC_LOAD_WEAK_DYLIB = 0x80000018

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
            name_bytes = data[pos + name_off : pos + name_off + 60]
            if b'MobileCoreServices' in name_bytes:
                print(f'  → Patch: LC_LOAD_DYLIB @ offset {pos} → LC_LOAD_WEAK_DYLIB')
                struct.pack_into('<I', data, pos, LC_LOAD_WEAK_DYLIB)
                found = True
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
    sys.exit(0)
else:
    print('MobileCoreServices não encontrado ou já é weak.')
    sys.exit(0)
