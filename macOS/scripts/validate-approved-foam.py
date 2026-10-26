#!/usr/bin/env python3
"""Validate the self-contained, byte-preserved approved v13 foam pack."""
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import struct
import sys
import zlib


class InvalidFoam(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidFoam(message)


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def all_numbers_finite(value):
    if isinstance(value, dict):
        return all(all_numbers_finite(item) for item in value.values())
    if isinstance(value, list):
        return all(all_numbers_finite(item) for item in value)
    return not isinstance(value, float) or math.isfinite(value)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative_file(value, prefix=None, suffix=None):
    require(isinstance(value, str) and value, 'Empty resource path.')
    path = PurePosixPath(value)
    require(not path.is_absolute() and '..' not in path.parts and path.as_posix() == value,
            'Resource paths must stay inside the foam pack.')
    if prefix:
        require(path.parts[0] == prefix and len(path.parts) == 2, 'Unexpected resource directory.')
    if suffix:
        require(path.suffix == suffix, 'Unexpected resource extension.')
    return value


def read_json(path):
    value = json.loads(path.read_text())
    require(all_numbers_finite(value), 'Non-finite number in ' + path.name)
    return value


def validate_png(path):
    data = path.read_bytes()
    require(len(data) >= 33 and data[:8] == b'\x89PNG\r\n\x1a\n'
            and data[12:16] == b'IHDR', 'Invalid foam PNG: ' + path.name)
    width, height, depth, colour, compression, filtering, interlace = struct.unpack('>IIBBBBB', data[16:29])
    require(0 < width <= 8192 and 0 < height <= 8192
            and (depth, colour, compression, filtering, interlace) == (8, 6, 0, 0, 0),
            'Invalid approved PNG dimensions or format: ' + path.name)
    offset, chunks, pixels, saw_end = 8, [], bytearray(), False
    while offset + 12 <= len(data):
        length = struct.unpack('>I', data[offset:offset + 4])[0]
        end = offset + 12 + length
        require(end <= len(data), 'Truncated foam PNG: ' + path.name)
        kind = data[offset + 4:offset + 8]
        checksum = struct.unpack('>I', data[end - 4:end])[0]
        require(zlib.crc32(data[offset + 4:end - 4]) == checksum,
                'Damaged foam PNG: ' + path.name)
        chunks.append(kind)
        if kind == b'IHDR':
            require(len(chunks) == 1 and length == 13, 'Invalid PNG header: ' + path.name)
        if kind == b'IDAT':
            pixels.extend(data[offset + 8:end - 4])
        offset = end
        if kind == b'IEND':
            saw_end = length == 0 and offset == len(data)
            break
    require(saw_end and pixels and chunks.count(b'IHDR') == 1, 'Incomplete foam PNG: ' + path.name)
    decoder = zlib.decompressobj()
    raw = decoder.decompress(pixels, height * (1 + width * 4) + 1)
    require(decoder.eof and not decoder.unused_data and not decoder.unconsumed_tail
            and len(raw) == height * (1 + width * 4)
            and all(raw[row * (1 + width * 4)] <= 4 for row in range(height)),
            'Invalid PNG pixel data: ' + path.name)


def fraction_point(value):
    return (isinstance(value, dict) and set(value) == {'x', 'y'}
            and all(finite(value[axis]) and 0 <= value[axis] <= 1 for axis in ('x', 'y')))


def validate(directory):
    directory = Path(directory)
    require(directory.is_dir() and not directory.is_symlink(), 'Missing foam resource directory.')
    metadata = read_json(directory / 'metadata.json')
    require(isinstance(metadata, dict), 'Foam metadata must be an object.')
    expected_values = {'schemaVersion': 3, 'objectCount': 36, 'originalObjectCount': 8,
                       'sourceCanvas': 1254, 'frameRate': 60, 'referenceCut': 1.81,
                       'normalRestTime': 3.65, 'releaseDuration': 1.4,
                       'baseAssetFile': 'figma-assets/1ce55.png', 'sequenceFile': 'sequence.json',
                       'waterGeometryFile': 'water-geometry.json'}
    require(all(type(metadata.get(key)) is type(value) and metadata[key] == value
                for key, value in expected_values.items()), 'Invalid schema 3 foam constants.')
    objects = metadata.get('objects')
    require(isinstance(objects, list) and len(objects) == 36, 'Expected 36 persistent foam objects.')
    by_id = {}
    for item in objects:
        require(isinstance(item, dict) and isinstance(item.get('id'), str)
                and re.fullmatch(r'\d+:\d+', item['id']) and item['id'] not in by_id,
                'Invalid or duplicate foam object ID.')
        relative_file(item.get('file'), 'figma-assets', '.png')
        require(type(item.get('original')) is bool and fraction_point(item.get('pivot'))
                and fraction_point(item.get('foot')), 'Invalid foam pivot, foot, or original flag.')
        by_id[item['id']] = item
    require(len({item['file'] for item in objects}) == 36, 'Foam assets must preserve all 36 identities.')
    originals = {item['id'] for item in objects if item['original']}
    require(len(originals) == 8, 'Expected eight original foam objects.')

    sequence = read_json(directory / metadata['sequenceFile'])
    require(sequence.get('canvas') == [1254, 1254] and sequence.get('fps') == 60
            and sequence.get('videoFrameCount') == 704 and sequence.get('chapterFrames') == 352
            and sequence.get('baseAssetFile') == metadata['baseAssetFile'], 'Invalid approved timeline header.')
    frames = sequence.get('frames')
    require(isinstance(frames, list) and len(frames) == 729, 'Expected the complete 729-frame approved sequence.')
    frame_ids, masks, normal = set(), {relative_file(sequence.get('maskFile'), 'anchors', '.json')}, []
    for frame in frames:
        require(isinstance(frame, dict) and isinstance(frame.get('id'), str)
                and frame['id'] not in frame_ids, 'Invalid or duplicate foam frame ID.')
        frame_ids.add(frame['id'])
        require(finite(frame.get('timeSeconds')) and 0 <= frame['timeSeconds'] <= 4.46,
                'Invalid foam frame time.')
        masks.add(relative_file(frame.get('maskFile', sequence['maskFile']), 'anchors', '.json'))
        for name in ('maskOffsetX', 'maskOffsetY', 'maskHorizontalScale', 'physicalOpeningOffset',
                     'sinkSourceTimeSeconds', 'sinkElapsedSeconds', 'branchElapsedSeconds', 'inertiaPhase'):
            require(name not in frame or finite(frame[name]), 'Invalid numeric frame field: ' + name)
        require('maskHorizontalScale' not in frame or frame['maskHorizontalScale'] > 0,
                'Invalid foam mask scale.')
        slots = frame.get('slots')
        require(isinstance(slots, list) and 0 < len(slots) <= 36, 'Missing foam frame slots.')
        ids = set()
        for slot in slots:
            require(isinstance(slot, dict) and slot.get('id') in by_id and slot['id'] not in ids,
                    'Unknown or duplicate foam frame object.')
            ids.add(slot['id'])
            require(slot.get('assetFile') == by_id[slot['id']]['file'], 'Foam asset identity changed.')
            require(all(finite(slot.get(name)) for name in ('x', 'y', 'width', 'height', 'opacity'))
                    and 0 < slot['width'] <= 1254 and 0 < slot['height'] <= 1254
                    and 0 <= slot['opacity'] <= 1 and type(slot.get('mirrorX')) is bool
                    and type(slot.get('maskActive')) is bool, 'Invalid foam slot geometry or visibility.')
            for name in ('surfaceReveal', 'localMaskOffsetY', 'streamPhase', 'streamRadius', 'inertiaPhase',
                         'surfaceX', 'surfaceY', 'supportX', 'supportY', 'frontImmersion', 'flowDepth', 'occlusionDepthY'):
                require(name not in slot or finite(slot[name]), 'Invalid numeric slot field: ' + name)
            require('surfaceReveal' not in slot or 0 <= slot['surfaceReveal'] <= 1,
                    'Invalid foam surface reveal.')
        if 'videoIndex' in frame:
            require(type(frame['videoIndex']) is int and type(frame.get('chapter')) is int
                    and frame['chapter'] in (0, 1), 'Invalid normal timeline index or chapter.')
            normal.append(frame)
    require(len(normal) == 704 and [f['videoIndex'] for f in normal] == list(range(704)),
            'Normal timeline indices must include all 704 approved samples in order.')
    require({slot['id'] for frame in normal for slot in frame['slots']} == set(by_id),
            'Persistent object inventory differs from the normal timeline.')
    for chapter in (0, 1):
        samples = [frame for frame in normal if frame['chapter'] == chapter]
        require(len(samples) == 352 and samples[0]['timeSeconds'] == 0
                and samples[-1]['timeSeconds'] == 4.46
                and all(a['timeSeconds'] <= b['timeSeconds'] for a, b in zip(samples, samples[1:])),
                'Invalid ordered chapter timeline.')
        for frame in (samples[0], samples[-1]):
            require({slot['id'] for slot in frame['slots']} == originals, 'Timeline rest identity differs.')
    rest = [f for f in normal if f['chapter'] == 0 and abs(f['timeSeconds'] - 3.65) < 1e-8]
    full = [f for f in normal if f['chapter'] == 0 and abs(f['timeSeconds'] - 67 / 60) < 1e-8]
    require(len(rest) == len(full) == 1 and {slot['id'] for slot in rest[0]['slots']} == originals
            and len(full[0]['slots']) == 33, 'Invalid authored rest or full-flow frame.')

    water = read_json(directory / metadata['waterGeometryFile'])
    require(type(water.get('xmin')) is int and type(water.get('xmax')) is int
            and 0 <= water['xmin'] < water['xmax'] < 1254 and isinstance(water.get('columns'), dict),
            'Invalid foam water geometry.')
    require(set(water['columns']) == {str(x) for x in range(water['xmin'], water['xmax'] + 1)},
            'Water geometry must include every contour column.')
    require(all(isinstance(pair, list) and len(pair) == 2
                and all(finite(y) for y in pair) and 0 <= pair[0] <= pair[1] < 1254
                for pair in water['columns'].values()), 'Invalid water contour samples.')
    for name in masks:
        mask = read_json(directory / name)
        require(mask.get('isMask') is True and all(finite(mask.get(key)) for key in ('x', 'y', 'width', 'height'))
                and mask['width'] > 0 and mask['height'] > 0 and isinstance(mask.get('paths'), list)
                and mask['paths'] and all(isinstance(path.get('data'), str) and path['data']
                                         for path in mask['paths']), 'Invalid approved foam mask.')

    pngs = {metadata['baseAssetFile'], *(item['file'] for item in objects)}
    expected = {'metadata.json', 'manifest.json', 'sequence.json', 'water-geometry.json'} | pngs | masks
    actual = set()
    for path in directory.rglob('*'):
        require(not path.is_symlink(), 'Foam resources must not contain symlinks.')
        if path.is_file():
            actual.add(path.relative_to(directory).as_posix())
    require(actual == expected, 'Foam pack contains missing or unexpected resources.')
    for name in sorted(pngs):
        validate_png(directory / name)
    manifest = read_json(directory / 'manifest.json')
    require(manifest.get('schemaVersion') == 1 and manifest.get('sourcePreview') == 'motion-v13-rim-preserved'
            and manifest.get('pngCopiedWithoutReencoding') is True
            and isinstance(manifest.get('filesSHA256'), dict)
            and set(manifest['filesSHA256']) == expected - {'manifest.json'}, 'Invalid foam source manifest.')
    require(all(re.fullmatch(r'[0-9a-f]{64}', value) and sha256(directory / name) == value
                for name, value in manifest['filesSHA256'].items()), 'Foam source hash differs from copied resources.')
    sources = manifest.get('sourceSHA256')
    require(isinstance(sources, dict) and sources
            and all(isinstance(name, str) and re.fullmatch(r'[0-9a-f]{64}', value)
                    for name, value in sources.items()), 'Missing source SHA256 proof.')
    source_prefix = 'Build/Preview/storyboard-template/motion-v13-rim-preserved/'
    require(all(sources.get(source_prefix + name) == manifest['filesSHA256'][name]
                for name in pngs | masks | {'sequence.json'})
            and sources.get('Build/Preview/storyboard-template/motion-v7/water-geometry.json')
                == manifest['filesSHA256']['water-geometry.json'], 'Copied resource SHA256 differs from source proof.')
    require(manifest.get('sequenceSourceSHA256') == sha256(directory / 'sequence.json'),
            'Approved sequence was changed instead of copied byte-for-byte.')
    return metadata


if __name__ == '__main__':
    try:
        require(len(sys.argv) == 2, 'Usage: python3 scripts/validate-approved-foam.py Resources/Foam')
        result = validate(Path(sys.argv[1]))
        print('Validated schema 3 foam: 36 persistent objects, 8 originals, complete approved v13 sequence.')
    except (InvalidFoam, OSError, ValueError, KeyError, TypeError, struct.error, zlib.error) as error:
        raise SystemExit('Invalid approved foam: ' + str(error))
