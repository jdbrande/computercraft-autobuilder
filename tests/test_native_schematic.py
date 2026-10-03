"""Cross-check native Lua decoding against the independent Python converter."""
import gzip
import importlib.util
from pathlib import Path
import struct
import unittest
from lupa.lua52 import LuaRuntime, LuaError, lua_type
from test_schem_converter import fixture, tag

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('schem_converter', ROOT/'tools/schem_converter.py')
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)


def native_value(value):
    if lua_type(value) == 'table':
        keys = list(value.keys())
        if keys and all(isinstance(k, (int, float)) for k in keys):
            return [native_value(value[i]) for i in range(1, len(keys)+1)]
        return {k.decode() if isinstance(k, bytes) else k: native_value(v) for k,v in value.items()}
    return value.decode() if isinstance(value, bytes) else value


class NativeSchematicTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(encoding=None)
        self.decode = self.lua.eval(b"require('autobuilder.blueprint.sponge').decode")

    def test_native_matches_python_for_raw_and_gzip_both_versions(self):
        entities = tag(9,'Entities',b'\x0a'+struct.pack('>i',1)+b'\0')
        offset = tag(11,'Offset',struct.pack('>iiii',3,-4,7,9))
        palettes = [None, [('stone_slab[type=double]',0),('minecraft:oak_door[half=upper]',1)],
                    [('minecraft:wall_torch[facing=east]',0),('minecraft:oak_log[axis=x]',1)]]
        for version in (2,3):
            for palette in palettes:
                for extra in ((),(offset,entities)):
                    raw = fixture(version,palette=palette,extra=extra)
                    for source in (raw,gzip.compress(raw)):
                        with self.subTest(version=version,palette=palette,extra=bool(extra),gzip=source!=raw):
                            actual=native_value(self.decode(source)); expected=converter.convert(source)
                            if actual['metadata']['issues']=={}: actual['metadata']['issues']=[]
                            self.assertEqual(actual,expected)

    def test_both_reject_malformed_schematic_varints_and_palette_ids(self):
        for raw in (fixture(data=b'\2\1\1\0'),fixture(data=b'\x80\0\1\1\0'),fixture(data=b'\0'),
                    fixture(palette=[('stone',0),('dirt',0)]),fixture()[:-1]):
            with self.subTest(source=raw[-20:]):
                with self.assertRaises(ValueError): converter.convert(raw)
                with self.assertRaises(LuaError): self.decode(raw)


if __name__ == '__main__':
    unittest.main()
