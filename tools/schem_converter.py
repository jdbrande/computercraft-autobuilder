#!/usr/bin/env python3
"""Bounded, standard-library Sponge .schem v2/v3 to AutoBuilder JSON converter."""
import argparse
import gzip
import io
import json
import re
import struct
from pathlib import Path

MAX_BYTES = 32 * 1024 * 1024
MAX_BLOCKS = 262144
MAX_PALETTE = 65536
AIR = {'minecraft:air', 'minecraft:cave_air', 'minecraft:void_air'}


class NBT:
    """Decode big-endian named binary tags with allocation and nesting bounds."""
    def __init__(self, data):
        self.data, self.pos, self.nodes = data, 0, 0

    def take(self, count):
        if count < 0 or count > len(self.data) - self.pos:
            raise ValueError('truncated or invalid NBT length')
        result = self.data[self.pos:self.pos + count]
        self.pos += count
        return result

    def number(self, fmt):
        return struct.unpack('>' + fmt, self.take(struct.calcsize(fmt)))[0]

    def string(self):
        try:
            return self.take(self.number('H')).decode('utf-8')
        except UnicodeError as exc:
            raise ValueError('invalid UTF-8 NBT string') from exc

    def count(self):
        n = self.number('i')
        if n < 0 or n > len(self.data):
            raise ValueError('invalid NBT collection length')
        return n

    def payload(self, kind, depth=0):
        self.nodes += 1
        if depth > 32 or self.nodes > 1000000:
            raise ValueError('NBT nesting or node limit exceeded')
        formats = {1:'b', 2:'h', 3:'i', 4:'q', 5:'f', 6:'d'}
        if kind in formats:
            return self.number(formats[kind])
        if kind == 7:
            return self.take(self.count())
        if kind == 8:
            return self.string()
        if kind == 9:
            element, count = self.number('B'), self.count()
            if count > 1000000 or element > 12 or (element == 0 and count):
                raise ValueError('invalid NBT list')
            return [self.payload(element, depth + 1) for _ in range(count)]
        if kind == 10:
            out = {}
            while True:
                child = self.number('B')
                if child == 0:
                    return out
                key = self.string()
                if key in out:
                    raise ValueError('duplicate NBT compound key')
                out[key] = self.payload(child, depth + 1)
        if kind in (11, 12):
            count = self.count()
            width, fmt = (4, 'i') if kind == 11 else (8, 'q')
            if count > 1000000:
                raise ValueError('NBT array limit exceeded')
            raw = self.take(count * width)
            return [v[0] for v in struct.iter_unpack('>' + fmt, raw)]
        raise ValueError('unknown NBT tag type')

    def read(self):
        if self.number('B') != 10:
            raise ValueError('NBT root must be compound')
        self.string()
        root = self.payload(10)
        if self.pos != len(self.data):
            raise ValueError('trailing NBT data')
        return root


def blockstate(text):
    if not isinstance(text, str) or len(text) > 4096:
        raise ValueError('invalid block state')
    match = re.fullmatch(r'([a-z0-9_.-]+(?::[a-z0-9_./-]+)?)(?:\[([^\[\]]+)\])?', text)
    if not match:
        raise ValueError('malformed block state: ' + text)
    name, props = match.groups()
    if ':' not in name:
        name = 'minecraft:' + name
    state = {}
    if props:
        for prop in props.split(','):
            pair = re.fullmatch(r'([a-z0-9_]+)=([a-z0-9_.-]+)', prop)
            if not pair or pair[1] in state:
                raise ValueError('malformed or duplicate block property')
            state[pair[1]] = pair[2]
    return {'name':name, 'state':dict(sorted(state.items()))}


def consumption(block):
    name, state = block['name'], block['state']
    if name in AIR or (name.endswith('_door') and state.get('half') == 'upper') or (name.endswith('_bed') and state.get('part') == 'head'):
        return name, 0
    aliases = {'minecraft:wall_torch':'minecraft:torch', 'minecraft:redstone_wall_torch':'minecraft:redstone_torch', 'minecraft:soul_wall_torch':'minecraft:soul_torch', 'minecraft:redstone_wire':'minecraft:redstone', 'minecraft:wheat':'minecraft:wheat_seeds', 'minecraft:carrots':'minecraft:carrot', 'minecraft:potatoes':'minecraft:potato', 'minecraft:beetroots':'minecraft:beetroot_seeds'}
    return aliases.get(name, name), 2 if name.endswith('_slab') and state.get('type') == 'double' else 1


def convert(source, *, max_bytes=MAX_BYTES, max_blocks=MAX_BLOCKS):
    """Return compact schema v1; source is gzip or raw NBT bytes. Raise ValueError."""
    if len(source) > max_bytes:
        raise ValueError('input byte limit exceeded')
    if source.startswith(b'\x1f\x8b'):
        try:
            with gzip.GzipFile(fileobj=io.BytesIO(source)) as stream:
                source = stream.read(max_bytes + 1)
        except (OSError, EOFError) as exc:
            raise ValueError('invalid gzip stream') from exc
    if len(source) > max_bytes:
        raise ValueError('expanded byte limit exceeded')
    root = NBT(source).read()
    root = root.get('Schematic', root)
    if not isinstance(root, dict):
        raise ValueError('Schematic must be compound')
    version = root.get('Version')
    if type(version) is not int or version not in (2, 3):
        raise ValueError('only Sponge schematic versions 2 and 3 are supported')
    if type(root.get('DataVersion')) is not int or root['DataVersion'] < 0:
        raise ValueError('missing or invalid DataVersion')
    size = {}
    for axis, field in [('x','Width'), ('y','Height'), ('z','Length')]:
        value = root.get(field)
        if type(value) is not int or not -32768 <= value <= 65535 or value == 0:
            raise ValueError('invalid schematic dimension')
        size[axis] = value & 65535
    volume = size['x'] * size['y'] * size['z']
    if volume > max_blocks:
        raise ValueError('block volume limit exceeded')
    container = root.get('Blocks') if version == 3 else root
    if not isinstance(container, dict):
        raise ValueError('missing block container')
    palette = container.get('Palette')
    if not isinstance(palette, dict) or not 1 <= len(palette) <= MAX_PALETTE:
        raise ValueError('missing or oversized block palette')
    indexed = {}
    for text, index in palette.items():
        if type(index) is not int or not 0 <= index <= 2147483647 or index in indexed:
            raise ValueError('invalid or duplicate palette index')
        indexed[index] = blockstate(text)
    indices = sorted(indexed)
    remap = {old:new + 1 for new, old in enumerate(indices)}
    entries = [indexed[old] for old in indices]
    data = container.get('Data' if version == 3 else 'BlockData')
    if not isinstance(data, bytes):
        raise ValueError('missing block data byte array')
    runs, requirements = [], {}
    count = value = shift = 0
    for byte in data:
        if shift == 28 and byte > 7:
            raise ValueError('varint overflow')
        value |= (byte & 127) << shift
        if byte & 128:
            shift += 7
            if shift > 28:
                raise ValueError('varint too long')
            continue
        if shift and byte == 0:
            raise ValueError('noncanonical varint')
        if value not in remap:
            raise ValueError('block references unknown palette index')
        count += 1
        if count > volume:
            raise ValueError('block data exceeds volume')
        entry = remap[value]
        if runs and runs[-1]['id'] == entry:
            runs[-1]['count'] += 1
        else:
            runs.append({'id':entry, 'count':1})
        item, amount = consumption(entries[entry - 1])
        if amount:
            requirements[item] = requirements.get(item, 0) + amount
        value = shift = 0
    if shift or count != volume:
        raise ValueError('truncated block data or volume mismatch')
    offset = root.get('Offset', [0, 0, 0])
    if not isinstance(offset, list) or len(offset) != 3 or any(type(v) is not int for v in offset):
        raise ValueError('invalid schematic offset')
    issues = []
    for key, owner, label in [('Entities',root,'entities'), ('BlockEntities',container,'block entities')]:
        if key in owner:
            if not isinstance(owner[key], list):
                raise ValueError('invalid ' + key)
            if owner[key]:
                issues.append(f'Unsupported {label}: {len(owner[key])}; entity/NBT data is not restored')
    if 'Biomes' in root or 'BiomeData' in root:
        issues.append('Unsupported biomes: biome data is not restored')
    metadata = {'sourceVersion':version, 'dataVersion':root['DataVersion'], 'offset':dict(zip(('x','y','z'),offset)), 'issues':issues}
    return {'schema':1, 'size':size, 'palette':entries, 'runs':runs, 'metadata':metadata, 'requirements':dict(sorted(requirements.items()))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    try:
        with args.input.open('rb') as stream:
            result = convert(stream.read(MAX_BYTES + 1))
        encoded = json.dumps(result, sort_keys=True, separators=(',', ':'), allow_nan=False) + '\n'
        with args.output.open('x', encoding='utf-8') as stream:
            stream.write(encoded)
    except (OSError, ValueError) as exc:
        parser.exit(1, f'conversion failed: {exc}\n')


if __name__ == '__main__':
    main()
