#!/usr/bin/env python3
"""Deterministic compressed inputs made by Python zlib for native Lua tests."""
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1] / 'tests/fixtures/native'

def gzip_bytes(data, level=6, strategy=zlib.Z_DEFAULT_STRATEGY, optional=False):
    compressor = zlib.compressobj(level, zlib.DEFLATED, -15, strategy=strategy)
    body = compressor.compress(data) + compressor.flush()
    header = b'\x1f\x8b\x08' + bytes([30 if optional else 0]) + b'\0'*6
    if optional:
        header += b'\x03\0abcfixture\0comment\0'
        header += struct.pack('<H', zlib.crc32(header) & 65535)
    return header + body + struct.pack('<II', zlib.crc32(data), len(data))

def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    payload = (b'native turtle schematic\0' * 6000) + bytes(range(256)) * 8
    (ROOT/'payload.bin').write_bytes(payload)
    for name, level, strategy in [('stored',0,zlib.Z_DEFAULT_STRATEGY),('fixed',6,zlib.Z_FIXED),('dynamic',6,zlib.Z_DEFAULT_STRATEGY)]:
        (ROOT/(name+'.gz')).write_bytes(gzip_bytes(payload,level,strategy))
    (ROOT/'optional.gz').write_bytes(gzip_bytes(payload,optional=True))
    (ROOT/'empty.gz').write_bytes(gzip_bytes(b''))
    import sys
    sys.path.insert(0, str(ROOT.parents[1]))
    from test_schem_converter import fixture
    for version in (2,3):
        (ROOT/('sponge-v%d.bin'%version)).write_bytes(fixture(version))
        (ROOT/('sponge-v%d.gz'%version)).write_bytes(gzip_bytes(fixture(version)))

if __name__ == '__main__':
    main()
