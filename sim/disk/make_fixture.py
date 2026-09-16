"""Create original test patterns, not Apple software, in WOZ1/WOZ2 containers."""
import pathlib
import struct
import zlib

out = pathlib.Path('sim/obj_dir/disk')
out.mkdir(parents=True, exist_ok=True)

def chunk(name, data):
    return name.encode() + struct.pack('<I', len(data)) + data

for version, blocks in ((1, 13), (2, 13), (2, 40)):
    info = bytearray(60)
    info[0:2] = bytes((version, 1))
    info[5:37] = b'Apple III regression fixture    '
    info[37] = 1
    info[39] = 32
    tmap = bytearray([255] * 160)
    tmap[0:2] = bytes((0, 0))
    tmap[3:6] = bytes((1, 1, 1))
    tracks = [bytes((i * 13 + track * 37) & 255 for i in range(blocks * 512)) for track in range(2)]
    if version == 1:
        records = bytearray()
        for track in tracks:
            records += track[:6646] + struct.pack('<HHHBBH', 6250, 50000, 0xffff, 0, 0, 0)
        data = chunk('INFO', info) + chunk('TMAP', tmap) + chunk('TRKS', records)
    else:
        table = bytearray(1280)
        for i in range(2):
            struct.pack_into('<HHI', table, i * 8, 3 + i * blocks, blocks, 50000)
        data = chunk('INFO', info) + chunk('TMAP', tmap) + chunk('TRKS', table + b''.join(tracks))
    raw = f'WOZ{version}'.encode() + b'\xff\x0a\x0d\x0a' + struct.pack('<I', zlib.crc32(data)) + data
    suffix = '-large' if blocks > 13 else ''
    (out / f'fixture{version}{suffix}.woz').write_bytes(raw)
