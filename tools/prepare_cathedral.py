#!/usr/bin/env python3
"""Prepare bounded, simplified planning sections from the supplied cathedral schematic.

This is a documented approximation, not a fidelity converter or an unattended
multi-section build dispatcher. The original input is never changed.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re

from schem_converter import AIR, MAX_BYTES, convert

SECTION = 32
MAX_DESKTOP_VOLUME = 32_000_000


def replacement(name, y):
    """Return a full cube or air, and the reason for this explicit simplification."""
    n = name.removeprefix('minecraft:')
    if name in AIR:
        return 'air', 'original air'
    if n.endswith(('_button', '_pressure_plate', '_trapdoor', '_door', '_fence_gate', '_candle', '_carpet', '_sign', '_banner', '_head', '_skull')) or n == 'candle':
        return 'air', 'omit unsupported decoration or interactive fixture'
    if n in {'dirt', 'grass_block', 'coarse_dirt', 'rooted_dirt', 'podzol', 'bedrock', 'gravel', 'sand', 'soul_sand'} or n == 'stone' and y < 32:
        return 'air', 'omit surrounding terrain and buried natural stone below source Y=32'
    if n in {'water', 'lava', 'barrier', 'light', 'structure_void', 'command_block', 'fire', 'end_portal_frame'}:
        return 'air', 'omit fluids, invisible helpers and special blocks'
    if 'glass' in n or n == 'iron_bars' or n.endswith('_fence'):
        return 'glass', 'clear full-block glazing or railing substitute'
    if n.endswith(('_planks', '_log', '_wood', '_stem', '_hyphae')) or re.fullmatch(r'(oak|spruce|birch|jungle|acacia|dark_oak|mangrove|cherry)_(stairs|slab)', n):
        return ('spruce_planks' if 'spruce' in n or 'dark_oak' in n else 'oak_planks'), 'full-block timber substitute'
    if 'quartz' in n or 'diorite' in n or n in {'white_concrete', 'white_terracotta', 'white_wool', 'iron_block'}:
        return 'polished_diorite', 'obtainable pale masonry substitute'
    if any(s in n for s in ('black', 'deepslate', 'prismarine', 'copper')) or n in {'coal_block', 'obsidian', 'dried_kelp_block'}:
        return 'cobbled_deepslate', 'dark full-block roof or masonry substitute'
    if 'sandstone' in n or n in {'gold_block', 'yellow_concrete', 'yellow_glazed_terracotta'}:
        return 'sandstone', 'warm full-block masonry substitute'
    if 'granite' in n or n in {'bricks', 'brick_slab', 'brick_stairs', 'terracotta', 'red_wool', 'red_concrete', 'red_concrete_powder', 'orange_glazed_terracotta', 'red_glazed_terracotta', 'red_terracotta', 'magma_block'}:
        return 'bricks', 'red full-block masonry substitute'
    if any(s in n for s in ('stone', 'andesite')) and not any(s in n for s in ('button', 'pressure_plate', 'redstone', 'stonecutter')):
        return 'stone_bricks', 'neutral full-block masonry substitute'
    if n.endswith(('_terracotta', '_concrete', '_concrete_powder', '_wool')):
        return 'stone_bricks', 'neutral substitute for decorative colored blocks'
    return 'air', 'omit unsupported decoration, furniture, vegetation or mechanism'


def encode(values):
    runs = []
    for value in values:
        if runs and runs[-1]['id'] == value + 1:
            runs[-1]['count'] += 1
        else:
            runs.append({'id': value + 1, 'count': 1})
    return runs


def write_json(path, value):
    path.write_text(json.dumps(value, separators=(',', ':'), sort_keys=True) + '\n')


def prepare(source, output):
    if output.exists():
        raise ValueError('Output must be a new directory')
    with source.open('rb') as stream:
        raw = stream.read(MAX_BYTES + 1)
    data = convert(raw, max_blocks=MAX_DESKTOP_VOLUME)
    width, height, length = (data['size'][axis] for axis in ('x', 'y', 'z'))
    area = width * length
    names = ['minecraft:air', 'minecraft:stone_bricks', 'minecraft:polished_diorite',
             'minecraft:cobbled_deepslate', 'minecraft:bricks', 'minecraft:sandstone',
             'minecraft:spruce_planks', 'minecraft:oak_planks', 'minecraft:glass']
    indices = {name: i for i, name in enumerate(names)}
    palette = [{'name': name, 'state': {}} for name in names]
    cells = bytearray()
    changes = Counter()
    requirements = Counter()
    bounds = [width, height, length, -1, -1, -1]
    original_non_air = omitted = 0
    for run in data['runs']:
        entry = data['palette'][run['id'] - 1]
        left = run['count']
        while left:
            start = len(cells)
            y = start // area
            amount = min(left, area - start % area)
            target, reason = replacement(entry['name'], y)
            target = 'minecraft:' + target
            if entry['name'] not in AIR:
                original_non_air += amount
                changes[(entry['name'], target, reason)] += amount
                if target in AIR:
                    omitted += amount
            idx = indices[target]
            cells.extend(bytes([idx]) * amount)
            if idx:
                requirements[target] += amount
                for pos in range(start, start + amount):
                    x, z = pos % width, pos // width % length
                    bounds[0] = min(bounds[0], x); bounds[1] = min(bounds[1], y); bounds[2] = min(bounds[2], z)
                    bounds[3] = max(bounds[3], x); bounds[4] = max(bounds[4], y); bounds[5] = max(bounds[5], z)
            left -= amount
    output.mkdir(parents=True)
    source_hash = hashlib.sha256(raw).hexdigest()
    sections = []
    pilot = None
    for oy in range(0, height, SECTION):
        for oz in range(0, length, SECTION):
            for ox in range(0, width, SECTION):
                sx, sy, sz = min(SECTION, width-ox), min(SECTION, height-oy), min(SECTION, length-oz)
                part = bytearray()
                for y in range(oy, oy+sy):
                    for z in range(oz, oz+sz):
                        start = (y*length+z)*width+ox
                        part.extend(cells[start:start+sx])
                counts = Counter(part)
                count = len(part)-counts[0]
                if not count:
                    continue
                name = f'cathedral-x{ox:03d}-y{oy:03d}-z{oz:03d}'
                req = {names[i]: n for i,n in counts.items() if i}
                result = {'schema':1, 'size':{'x':sx,'y':sy,'z':sz}, 'palette':palette,
                          'runs':encode(part), 'requirements':req,
                          'metadata':{'issues':[], 'simplification':{'sourceFile':source.name,
                            'sourceSHA256':source_hash, 'sectionOffset':{'x':ox,'y':oy,'z':oz},
                            'sourceIssues':data['metadata']['issues'], 'entityDataRestored':False,
                            'profile':'classic-cathedral-full-cubes-v1'}}}
                path = output/(name+'.json'); write_json(path,result)
                sections.append({'name':name, 'file':path.name, 'offset':{'x':ox,'y':oy,'z':oz},
                    'size':result['size'],'blocks':count,'requirements':req,'bytes':path.stat().st_size,
                    'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
                # A small actual source patch, all cells exposed to inspection.
                if pilot is None:
                    for y in range(sy):
                        for z in range(0,sz,8):
                            for x in range(0,sx,8):
                                px,pz=min(8,sx-x),min(8,sz-z)
                                patch=bytearray()
                                for row in range(z,z+pz): patch.extend(part[(y*sz+row)*sx+x:(y*sz+row)*sx+x+px])
                                pc=Counter(patch); solid=len(patch)-pc[0]
                                if solid>=16:
                                    pilot={'schema':1,'size':{'x':px,'y':1,'z':pz},'palette':palette,
                                        'runs':encode(patch),'requirements':{names[i]:n for i,n in pc.items() if i},
                                        'metadata':{'issues':[],'sourceSection':name,'sourceOffset':{'x':ox+x,'y':oy+y,'z':oz+z},
                                          'purpose':'Independent single-layer placement pilot; not full cathedral construction'}}
                                    break
                            if pilot: break
                        if pilot: break
    manifest={'schema':1,'project':'classic-cathedral-simplified','status':'planning-sections-not-unattended-build-ready',
        'source':source.name,'sourceSHA256':source_hash,'size':data['size'],'sourceOffset':data['metadata']['offset'],
        'originalBlocks':original_non_air,'plannedBlocks':sum(requirements.values()),'omittedBlocks':omitted,
        'occupiedBounds':{'min':dict(zip(('x','y','z'),bounds[:3])),'max':dict(zip(('x','y','z'),bounds[3:]))},
        'sectionSize':SECTION,'order':'source Y, then Z, then X; use offset plus chosen world base origin',
        'sourceIssues':data['metadata']['issues'],'requirements':dict(requirements),'sections':sections}
    write_json(output/'catalog.json',manifest)
    write_json(output/'substitutions.json',{'changes':[{'source':a,'replacement':b,'reason':r,'count':n} for (a,b,r),n in sorted(changes.items())], 'allOutputStates':{}, 'entityDataRestored':False})
    assert pilot, 'No suitable pilot patch'
    write_json(output/'cathedral-pilot.json',pilot)
    (output/'materials.csv').write_text('item,count\n'+''.join(f'{name},{n}\n' for name,n in sorted(requirements.items())))
    print(json.dumps({k:manifest[k] for k in ('size','originalBlocks','plannedBlocks','omittedBlocks','occupiedBounds','requirements')},indent=2))
    print(f'{len(sections)} non-empty sections; total JSON bytes: {sum(p.stat().st_size for p in output.glob("*.json"))}')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path); parser.add_argument('output',type=Path)
    args=parser.parse_args(); prepare(args.source,args.output)
