import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from collections import Counter

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))


def encoded(value):
    return (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()


class StreamCatalogTests(unittest.TestCase):
    def fixture(self, path):
        sections = []
        for x, width in [(0, 32), (32, 1)]:
            # A full lower floor and upper floor; leaves an empty middle layer.
            part = dict(schema=1, size=dict(x=width, y=3, z=1),
                        palette=[dict(name='minecraft:air', state={}), dict(name='minecraft:stone', state={})],
                        runs=[dict(id=2, count=width), dict(id=1, count=width), dict(id=2, count=width)],
                        metadata={}, requirements={'minecraft:stone': width * 2})
            raw = encoded(part)
            name = f'part-{x}.json'
            (path / name).write_bytes(raw)
            sections.append(dict(file=name, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                                 offset=dict(x=x, y=0, z=0), size=part['size'], blocks=width*2,
                                 requirements=part['requirements']))
        catalog = dict(schema=1, project='fixture', size=dict(x=33, y=3, z=1),
                       plannedBlocks=66, requirements={'minecraft:stone': 66}, sections=sections)
        (path / 'catalog.json').write_bytes(encoded(catalog))
        return catalog

    def test_layers_preserve_materials_cells_edges_and_global_order(self):
        import stream_catalog
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory)
            self.fixture(source)
            stream_catalog.prepare(source, source / 'stream', page_size=2)
            root = json.loads((source / 'stream/index.json').read_bytes())
            entries = []
            counts = Counter()
            for page in root['pages']:
                raw = (source / 'stream' / page['file']).read_bytes()
                self.assertEqual(len(raw), page['bytes'])
                self.assertEqual(hashlib.sha256(raw).hexdigest(), page['sha256'])
                values = json.loads(raw)['entries']
                self.assertEqual(len(values), page['count'])
                self.assertLessEqual(len(values), 2)
                entries.extend(values)
            self.assertEqual([(e['offset']['y'], e['offset']['x']) for e in entries], [(0, 0), (0, 32), (2, 0), (2, 32)])
            self.assertEqual([e['size']['x'] for e in entries], [32, 1, 32, 1])
            for entry in entries:
                raw = (source / 'stream' / entry['file']).read_bytes()
                self.assertEqual(len(raw), entry['bytes'])
                self.assertEqual(hashlib.sha256(raw).hexdigest(), entry['sha256'])
                part = json.loads(raw)
                self.assertEqual(part['size']['y'], 1)
                self.assertEqual(sum(r['count'] for r in part['runs']), entry['blockCount'])
                counts.update(part['requirements'])
                self.assertEqual(part['requirements'], entry['requirements'])
            self.assertEqual(dict(counts), {'minecraft:stone': 66})
            self.assertEqual(root['requirements'], dict(counts))
            self.assertEqual(root['totalBlocks'], 66)

    def test_rejects_source_corruption_and_traversal(self):
        import stream_catalog
        for mutation in ('hash', 'path', 'counts'):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                source = Path(directory)
                catalog = self.fixture(source)
                if mutation == 'hash':
                    (source / 'part-0.json').write_text('broken')
                elif mutation == 'path':
                    catalog['sections'][0]['file'] = '../outside.json'
                else:
                    catalog['requirements']['minecraft:stone'] = 67
                (source / 'catalog.json').write_bytes(encoded(catalog))
                with self.assertRaises(ValueError):
                    stream_catalog.prepare(source, source / 'stream')

    def test_checked_in_stream_matches_source_requirements_and_is_bounded(self):
        base = Path(__file__).resolve().parents[1] / 'blueprints/classic-cathedral'
        self.assertTrue((base / 'stream/index.json').exists(), 'stream assets must be generated')
        source = json.loads((base / 'catalog.json').read_bytes())
        root = json.loads((base / 'stream/index.json').read_bytes())
        counts = Counter()
        total = 0
        previous = (-1, -1, -1)
        for descriptor in root['pages']:
            raw = (base / 'stream' / descriptor['file']).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), descriptor['sha256'])
            self.assertLessEqual(len(raw), 1048576)
            entries = json.loads(raw)['entries']
            self.assertEqual(len(entries), descriptor['count'])
            self.assertLessEqual(len(entries), 128)
            for entry in entries:
                offset = entry['offset']
                position = tuple(offset[k] for k in ('y', 'z', 'x'))
                self.assertGreater(position, previous)
                previous = position
                raw = (base / 'stream' / entry['file']).read_bytes()
                self.assertEqual(len(raw), entry['bytes'])
                self.assertEqual(hashlib.sha256(raw).hexdigest(), entry['sha256'])
                self.assertLessEqual(len(raw), 1048576)
                chunk = json.loads(raw)
                real = Counter()
                volume = 0
                for run in chunk['runs']:
                    volume += run['count']
                    name = chunk['palette'][run['id'] - 1]['name']
                    if name != 'minecraft:air':
                        real[name] += run['count']
                self.assertEqual(volume, chunk['size']['x'] * chunk['size']['z'])
                self.assertEqual(dict(real), entry['requirements'])
                self.assertEqual(dict(real), chunk['requirements'])
                self.assertEqual(sum(real.values()), entry['blockCount'])
                self.assertGreater(entry['blockCount'], 0)
                counts.update(real)
                total += entry['blockCount']
        self.assertEqual(total, root['totalBlocks'])
        self.assertEqual(total, source['plannedBlocks'])
        self.assertEqual(dict(counts), source['requirements'])
        self.assertEqual(dict(counts), root['requirements'])


if __name__ == '__main__':
    unittest.main()
