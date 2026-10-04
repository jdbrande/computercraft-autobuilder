import gzip
import importlib.util
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[1] / 'tools/schem_converter.py'

def string(s):
    b = s.encode(); return struct.pack('>H', len(b)) + b

def tag(kind, name, payload):
    return bytes([kind]) + string(name) + payload

def compound(fields):
    return b''.join(fields) + b'\0'

def fixture(version=2, data=b'\0\1\1\0', palette=None, extra=(), width=2, block_extra=()):
    palette = palette or [('minecraft:air', 0), ('minecraft:oak_log[axis=x]', 1)]
    pal = tag(10, 'Palette', compound([tag(3, n, struct.pack('>i', i)) for n,i in palette]))
    block = pal + tag(7, 'Data' if version == 3 else 'BlockData', struct.pack('>i', len(data))+data)
    block += b''.join(block_extra)
    fields = [tag(3,'Version',struct.pack('>i',version)),tag(3,'DataVersion',struct.pack('>i',3700)),tag(2,'Width',struct.pack('>h',width)),tag(2,'Height',struct.pack('>h',1)),tag(2,'Length',struct.pack('>h',2))]
    fields += [tag(10,'Blocks',block+b'\0')] if version==3 else [block]
    fields.extend(extra)
    body = compound(fields)
    return tag(10, '', compound([tag(10,'Schematic',body)])) if version==3 else tag(10,'Schematic',body)

class ConverterTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(MODULE.exists(), 'converter implementation is missing')
        spec = importlib.util.spec_from_file_location('converter', MODULE)
        self.c = importlib.util.module_from_spec(spec); spec.loader.exec_module(self.c)

    def test_raw_v2_and_gzip_v3_retain_states_and_volume(self):
        for source in [fixture(), gzip.compress(fixture(3))]:
            result = self.c.convert(source)
            self.assertEqual(result['size'], {'x':2,'y':1,'z':2})
            self.assertEqual(result['palette'][1], {'name':'minecraft:oak_log','state':{'axis':'x'}})
            self.assertEqual(result['runs'], [{'id':1,'count':1},{'id':2,'count':2},{'id':1,'count':1}])
            self.assertEqual(result['requirements'], {'minecraft:oak_log':2})

    def test_rejects_truncation_unknown_palette_and_bad_varints(self):
        for source in [fixture()[:-1], fixture(data=b'\2\1\1\0'), fixture(data=b'\x80'),fixture(data=b'\x80\x80\x80\x80\x80\0'),fixture(data=b'\0'),fixture(data=b'\0'*5),fixture(width=0),fixture(palette=[('minecraft:air',0),('minecraft:stone',0)]),fixture(palette=[('stone[axis=x,axis=y]',0)])]:
            with self.subTest(source=source[-20:]), self.assertRaises(ValueError): self.c.convert(source)

    def test_entity_requirements_are_explicit_and_offset_preserved(self):
        extra=[tag(9,'Entities',b'\x0a'+struct.pack('>i',1)+b'\0'),tag(11,'Offset',struct.pack('>iiii',3,-3,4,5))]
        result=self.c.convert(fixture(extra=extra))
        self.assertEqual(result['metadata']['offset'], {'x':-3,'y':4,'z':5})
        self.assertTrue(any('entities' in x for x in result['metadata']['issues']))

    def test_bounds_and_trailing_data(self):
        with self.assertRaises(ValueError): self.c.convert(gzip.compress(fixture()), max_bytes=20)
        with self.assertRaises(ValueError): self.c.convert(fixture(), max_blocks=3)
        with self.assertRaises(ValueError): self.c.convert(fixture()+b'garbage')

    def test_cli_writes_deterministic_json_and_does_not_clobber(self):
        with tempfile.TemporaryDirectory() as d:
            src=Path(d)/'in.schem'; dst=Path(d)/'out.json'; src.write_bytes(fixture())
            result=subprocess.run([sys.executable,str(MODULE),str(src),str(dst)],capture_output=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(json.loads(dst.read_text())['schema'],1)
            result=subprocess.run([sys.executable,str(MODULE),str(src),str(dst)],capture_output=True)
            self.assertNotEqual(result.returncode,0)

if __name__=='__main__': unittest.main()
