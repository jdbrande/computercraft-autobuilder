import hashlib
import json
from pathlib import Path
import sys
import unittest
import tempfile

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
sys.path.insert(0, str(TOOLS))
import prepare_cathedral as cathedral


class CathedralTests(unittest.TestCase):
    def test_sections_preserve_offsets_counts_hashes_and_original_input(self):
        from test_schem_converter import fixture
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'sample.schem'
            raw = fixture(data=b'\0' * 80, palette=[('minecraft:quartz_block', 0)], width=40)
            source.write_bytes(raw)
            output = root / 'sections'
            cathedral.prepare(source, output)
            catalog = json.loads((output / 'catalog.json').read_text())
            self.assertEqual(source.read_bytes(), raw)
            self.assertEqual(catalog['plannedBlocks'], 80)
            self.assertEqual([s['offset']['x'] for s in catalog['sections']], [0, 32])
            for section in catalog['sections']:
                encoded = (output / section['file']).read_bytes()
                self.assertEqual(hashlib.sha256(encoded).hexdigest(), section['sha256'])
                part = json.loads(encoded)
                self.assertEqual(sum(r['count'] for r in part['runs']), section['blocks'])
                self.assertLessEqual(max(part['size'].values()), 32)
            with self.assertRaises(ValueError):
                cathedral.prepare(source, output)

    def test_terrain_rule_preserves_high_stone_but_omits_buried_natural_stone(self):
        self.assertEqual(cathedral.replacement('minecraft:stone', 31)[0], 'air')
        self.assertEqual(cathedral.replacement('minecraft:stone', 32)[0], 'stone_bricks')
        self.assertEqual(cathedral.replacement('minecraft:bedrock', 200)[0], 'air')

    def test_decorations_do_not_become_solid_blocks_due_to_color_keywords(self):
        for name in ('black_candle', 'black_banner', 'polished_blackstone_button', 'dark_oak_trapdoor'):
            self.assertEqual(cathedral.replacement('minecraft:' + name, 64)[0], 'air')

    def test_run_encoding_preserves_every_cell_including_air_and_boundaries(self):
        source = bytearray([0, 0, 1, 1, 1, 0, 8])
        runs = cathedral.encode(source)
        decoded = [r['id'] - 1 for r in runs for _ in range(r['count'])]
        self.assertEqual(decoded, list(source))
        self.assertEqual(runs[0], {'id': 1, 'count': 2})


if __name__ == '__main__':
    unittest.main()
