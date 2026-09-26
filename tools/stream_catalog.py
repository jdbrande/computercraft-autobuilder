#!/usr/bin/env python3
"""Create bounded layer-ordered streaming assets from verified converted sections."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile

MAX_BYTES = 1024 * 1024
AIR = {'minecraft:air', 'minecraft:cave_air', 'minecraft:void_air'}


def safe_path(value):
    return (isinstance(value, str) and len(value) <= 200
            and re.fullmatch(r'[A-Za-z0-9_./-]+', value)
            and all(part and not part.startswith('.') for part in value.split('/')))


def write(root, filename, value):
    raw = (json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n').encode()
    if len(raw) > MAX_BYTES:
        raise ValueError('stream asset exceeds 1 MiB')
    path = root / filename
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(raw)
    return dict(file=filename, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())


def runs_for(cells):
    runs = []
    for value in cells:
        if runs and runs[-1]['id'] == value:
            runs[-1]['count'] += 1
        else:
            runs.append(dict(id=value, count=1))
    return runs


def prepare(source, output, page_size=128):
    source, output = Path(source), Path(output)
    if not 1 <= page_size <= 128:
        raise ValueError('page size must be 1..128')
    if output.exists():
        raise ValueError('output already exists; choose a new directory')
    catalog = json.loads((source / 'catalog.json').read_bytes())
    if catalog.get('schema') != 1:
        raise ValueError('unsupported source catalog')
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix='.stream-', dir=output.parent))
    entries, requirements, occupied = [], Counter(), set()
    try:
        for descriptor in catalog['sections']:
            if not safe_path(descriptor['file']):
                raise ValueError('unsafe section path')
            path = source / descriptor['file']
            if not path.resolve().is_relative_to(source.resolve()):
                raise ValueError('section escapes source directory')
            raw = path.read_bytes()
            if len(raw) != descriptor['bytes'] or hashlib.sha256(raw).hexdigest() != descriptor['sha256']:
                raise ValueError('source section hash/size mismatch')
            part = json.loads(raw)
            size, offset = part['size'], descriptor['offset']
            if part.get('schema') != 1 or size != descriptor['size']:
                raise ValueError('invalid section dimensions/schema')
            for axis in ('x', 'y', 'z'):
                if (type(size[axis]) is not int or not 1 <= size[axis] <= 32
                        or type(offset[axis]) is not int or offset[axis] < 0
                        or offset[axis] + size[axis] > catalog['size'][axis]):
                    raise ValueError('section outside project bounds')
            for axis in ('x', 'z'):
                if offset[axis] % 32 or size[axis] != min(32, catalog['size'][axis] - offset[axis]):
                    raise ValueError('section must use the 32-cell grid')
            cells = []
            volume = size['x'] * size['y'] * size['z']
            for run in part['runs']:
                if (type(run['id']) is not int or not 1 <= run['id'] <= len(part['palette'])
                        or type(run['count']) is not int or not 1 <= run['count'] <= volume
                        or len(cells) + run['count'] > volume):
                    raise ValueError('invalid source runs')
                cells.extend([run['id']] * run['count'])
            if len(cells) != volume:
                raise ValueError('source runs do not cover volume')
            section_requirements = Counter()
            stride = size['x'] * size['z']
            for y in range(size['y']):
                layer = cells[y * stride:(y + 1) * stride]
                counts = Counter()
                for identifier in layer:
                    palette_entry = part['palette'][identifier - 1]
                    if palette_entry['name'] not in AIR:
                        if palette_entry['state']:
                            raise ValueError('stream source must use simplified full cubes')
                        counts[palette_entry['name']] += 1
                if not counts:
                    continue
                position = dict(x=offset['x'], y=offset['y'] + y, z=offset['z'])
                key = tuple(position[a] for a in ('y', 'z', 'x'))
                if key in occupied:
                    raise ValueError('overlapping source sections')
                occupied.add(key)
                chunk_size = dict(x=size['x'], y=1, z=size['z'])
                name = f"chunks/y{position['y']:03d}-z{position['z']:03d}-x{position['x']:03d}.json"
                chunk = dict(schema=1, size=chunk_size, palette=part['palette'], runs=runs_for(layer),
                             requirements=dict(counts), metadata=dict(project=catalog['project'], offset=position))
                entry = write(staging, name, chunk)
                entry.update(offset=position, size=chunk_size, blockCount=sum(counts.values()), requirements=dict(counts))
                entries.append(entry)
                section_requirements.update(counts)
            if dict(section_requirements) != part['requirements'] or dict(section_requirements) != descriptor['requirements'] or sum(section_requirements.values()) != descriptor['blocks']:
                raise ValueError('source section requirements mismatch')
            requirements.update(section_requirements)
        if dict(requirements) != catalog['requirements'] or sum(requirements.values()) != catalog['plannedBlocks']:
            raise ValueError('source catalog requirements mismatch')
        entries.sort(key=lambda e: tuple(e['offset'][a] for a in ('y', 'z', 'x')))
        pages = []
        for start in range(0, len(entries), page_size):
            batch = entries[start:start + page_size]
            page = write(staging, f'pages/{len(pages) + 1:04d}.json', dict(schema=1, entries=batch))
            page['count'] = len(batch)
            pages.append(page)
        root = dict(schema=1, project=catalog['project'], size=catalog['size'], requirements=dict(requirements),
                    totalBlocks=sum(requirements.values()), pages=pages)
        write(staging, 'index.json', root)
        staging.rename(output)
        return root
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    root = prepare(args.source, args.output)
    print(f"{root['totalBlocks']} blocks; {sum(p['count'] for p in root['pages'])} chunks; {len(root['pages'])} pages")


if __name__ == '__main__':
    main()
