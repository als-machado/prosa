"""
Converte todos os LC_LOAD_DYLIB para LC_LOAD_WEAK_DYLIB em frameworks e
dylibs de sistema que podem ter sido removidos no iOS 26.

Regra: qualquer entrada cujo path começa com:
  /System/Library/Frameworks/
  /usr/lib/swift/

…é convertida para weak. Se o framework existir no dispositivo, é carregado
normalmente. Se não existir, o dyld ignora em vez de matar o processo com
POSIX error 85 (EBADEXEC).

Entradas mantidas como hard (nunca tornadas weak):
  @rpath/          — frameworks embarcados no próprio bundle
  /usr/lib/libSystem.B.dylib
  /usr/lib/libobjc.A.dylib
  /usr/lib/libc++.1.dylib
  /usr/lib/libc++abi.dylib
"""
import struct, sys

path = sys.argv[1]

LC_LOAD_DYLIB      = 0x0000000C
LC_LOAD_WEAK_DYLIB = 0x80000018

ALWAYS_KEEP_HARD = {
    b'/usr/lib/libSystem.B.dylib',
    b'/usr/lib/libobjc.A.dylib',
    b'/usr/lib/libc++.1.dylib',
    b'/usr/lib/libc++abi.dylib',
}

def should_make_weak(name_bytes):
    name = bytes(name_bytes).split(b'\x00')[0]
    if name in ALWAYS_KEEP_HARD:
        return False
    if name.startswith(b'@rpath/'):
        return False
    if name.startswith(b'/System/Library/Frameworks/'):
        return True
    if name.startswith(b'/usr/lib/swift/'):
        return True
    return False

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
            name_off  = struct.unpack_from('<I', data, pos + 8)[0]
            name_bytes = data[pos + name_off : pos + name_off + 256]
            if should_make_weak(name_bytes):
                name_str = name_bytes.split(b'\x00')[0].decode('utf-8', errors='replace')
                print(f'  → weak: {name_str}')
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
    print('Patch aplicado.')
else:
    print('Nada para patchar (todos já são weak ou apenas @rpath/lib*).')
sys.exit(0)
