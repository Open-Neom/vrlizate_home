#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate the original Home lounge asset using Python's standard library.

Run from any directory: python3 tool/generate_showcase_lounge.py
No downloads, textures, external geometry, runtime plug-ins, or random inputs.
Coordinates: metres, +Y up, chair faces +Z, origin at assembly bounds centre on floor.
The generated geometry is original to VRlizate; see assets/showcase/NOTICE.md.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

PI = math.pi


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, scale):
    return tuple(x * scale for x in a)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def unit(a):
    length = math.sqrt(dot(a, a))
    return mul(a, 1 / length) if length > 1e-12 else (0.0, 1.0, 0.0)


def spow(value, power):
    return math.copysign(abs(value) ** power, value)


class Mesh:
    def __init__(self):
        self.positions = []
        self.triangles = []
        self.uvs = []

    def vertex(self, position, uv=(0.0, 0.0)):
        self.positions.append(position)
        self.uvs.append(uv)
        return len(self.positions) - 1

    def triangle(self, a, b, c, outward=None):
        face = cross(sub(self.positions[b], self.positions[a]),
                     sub(self.positions[c], self.positions[a]))
        if dot(face, face) < 1e-20:
            return
        if outward is not None and dot(face, outward) < 0:
            b, c = c, b
        self.triangles.append((a, b, c))

    def surface(self, function, u_steps, v_steps, outward):
        grid = [[self.vertex(function(i / u_steps, j / v_steps),
                             (i / u_steps, j / v_steps))
                 for j in range(v_steps + 1)] for i in range(u_steps + 1)]
        for i in range(u_steps):
            for j in range(v_steps):
                normal = outward((i + 0.5) / u_steps, (j + 0.5) / v_steps)
                a, b = grid[i][j], grid[i + 1][j]
                c, d = grid[i + 1][j + 1], grid[i][j + 1]
                self.triangle(a, b, c, normal)
                self.triangle(a, c, d, normal)

    def normals(self):
        # Weld only normal accumulation, keeping UV seams in the actual mesh.
        keys = [tuple(round(c, 7) for c in p) for p in self.positions]
        sums = {key: (0.0, 0.0, 0.0) for key in keys}
        for a, b, c in self.triangles:
            n = cross(sub(self.positions[b], self.positions[a]),
                      sub(self.positions[c], self.positions[a]))
            for index in (a, b, c):
                sums[keys[index]] = add(sums[keys[index]], n)
        return [unit(sums[key]) for key in keys]


class Lounge:
    def __init__(self):
        self.parts = {}
        self.materials = [
            self.material('Petrol upholstery', (0.055, 0.19, 0.18), 0.92),
            self.material('Upholstery piping', (0.095, 0.28, 0.25), 0.88),
            self.material('Brushed antique brass', (0.39, 0.27, 0.12), 0.39, 0.78),
            self.material('Graphite foot pads', (0.025, 0.032, 0.03), 0.90),
            self.material('Warm limestone', (0.69, 0.64, 0.53), 0.77),
            self.material('Ivory ceramic', (0.68, 0.61, 0.49), 0.48),
            self.material('Potting soil', (0.045, 0.027, 0.017), 1.0),
            self.material('Plant stems', (0.12, 0.10, 0.037), 0.92),
            self.material('Leaf forest', (0.035, 0.17, 0.065), 0.65),
            self.material('Leaf jade', (0.055, 0.235, 0.095), 0.63),
            self.material('Leaf new growth', (0.12, 0.29, 0.10), 0.67),
            self.material('Leaf midrib', (0.18, 0.29, 0.085), 0.78),
        ]

    @staticmethod
    def material(name, color, roughness, metallic=0.0):
        return {'name': name, 'pbrMetallicRoughness': {
            'baseColorFactor': [*color, 1.0], 'roughnessFactor': roughness,
            'metallicFactor': metallic}, 'doubleSided': False}

    def mesh(self, part, material):
        return self.parts.setdefault((part, material), Mesh())

    def rounded(self, part, material, center, radii, exponent=0.45):
        def point(u, v):
            latitude, longitude = PI * (u - 0.5), 2 * PI * v
            return add(center, (radii[0] * spow(math.cos(latitude), exponent) *
                                spow(math.cos(longitude), exponent),
                                radii[1] * spow(math.sin(latitude), exponent),
                                radii[2] * spow(math.cos(latitude), exponent) *
                                spow(math.sin(longitude), exponent)))
        self.mesh(part, material).surface(point, 20, 48,
                                          lambda u, v: sub(point(u, v), center))

    def tube(self, part, material, points, radii, sides=10, capped=True):
        mesh = self.mesh(part, material)
        rings = []
        tangents = []
        for i, (point, radius) in enumerate(zip(points, radii)):
            tangent = unit(sub(points[min(i + 1, len(points) - 1)],
                               points[max(0, i - 1)]))
            reference = (0, 1, 0) if abs(tangent[1]) < 0.9 else (1, 0, 0)
            side = unit(cross(tangent, reference))
            other = unit(cross(tangent, side))
            rings.append([mesh.vertex(add(point, mul(add(
                mul(side, math.cos(2 * PI * j / sides)),
                mul(other, math.sin(2 * PI * j / sides))), radius)),
                (j / sides, i / (len(points) - 1))) for j in range(sides)])
            tangents.append(tangent)
        for i in range(len(rings) - 1):
            for j in range(sides):
                a, b = rings[i][j], rings[i][(j + 1) % sides]
                c, d = rings[i + 1][(j + 1) % sides], rings[i + 1][j]
                outward = sub(mesh.positions[a], points[i])
                mesh.triangle(a, b, c, outward)
                mesh.triangle(a, c, d, outward)
        if capped:
            for i, normal in [(0, mul(tangents[0], -1)), (-1, tangents[-1])]:
                center = mesh.vertex(points[i])
                for j in range(sides):
                    mesh.triangle(center, rings[i][j], rings[i][(j + 1) % sides], normal)

    def lathe(self, part, material, center, profile, segments=48):
        mesh = self.mesh(part, material)
        rings = [[mesh.vertex(add(center, (r * math.cos(2 * PI * j / segments),
                                           y, r * math.sin(2 * PI * j / segments))),
                              (j / segments, i / (len(profile) - 1)))
                  for j in range(segments)] for i, (r, y) in enumerate(profile)]
        for i in range(len(profile) - 1):
            dr, dy = sub(profile[i + 1], profile[i])
            for j in range(segments):
                angle = 2 * PI * (j + 0.5) / segments
                normal = (dy * math.cos(angle), -dr, dy * math.sin(angle))
                a, b = rings[i][j], rings[i][(j + 1) % segments]
                c, d = rings[i + 1][(j + 1) % segments], rings[i + 1][j]
                mesh.triangle(a, b, c, normal)
                mesh.triangle(a, c, d, normal)

    def chair(self):
        part = 'LoungeChair'
        self.rounded(part, 0, (0, 0.51, 0.025), (0.505, 0.085, 0.445), 0.35)
        # Continuous rounded tub shell, with the back higher than the arms.
        def shell(u, v):
            angle, section = (u - 0.5) * 3.92, 2 * PI * v
            top = 0.77 + 0.31 * max(0, math.cos((u - 0.5) * PI)) ** 1.3
            radial = 0.072 * spow(math.cos(section), 0.6)
            return ((0.54 + radial) * math.sin(angle),
                    (top + 0.46) / 2 + (top - 0.46) / 2 * spow(math.sin(section), 0.6),
                    -(0.46 + radial) * math.cos(angle))
        def outward(u, v):
            angle, section = (u - 0.5) * 3.92, 2 * PI * v
            return (math.sin(angle) * math.cos(section), math.sin(section),
                    -math.cos(angle) * math.cos(section))
        mesh = self.mesh(part, 0)
        mesh.surface(shell, 48, 24, outward)
        for u, direction in [(0, -1), (1, 1)]:
            angle = (u - 0.5) * 3.92
            center = mesh.vertex((0.54 * math.sin(angle), 0.615, -0.46 * math.cos(angle)))
            ring = [mesh.vertex(shell(u, j / 24)) for j in range(24)]
            normal = (direction * math.cos(angle), 0, direction * math.sin(angle))
            for j in range(24):
                mesh.triangle(center, ring[j], ring[(j + 1) % 24], normal)
        # A separate inset back cushion and subtle sewn seat piping.
        self.rounded(part, 0, (0, 0.78, -0.31), (0.365, 0.205, 0.062), 0.5)
        piping = [(0.478 * spow(math.cos(a), 0.45), 0.559,
                   0.025 + 0.422 * spow(math.sin(a), 0.45))
                  for a in [2 * PI * i / 96 for i in range(97)]]
        self.tube(part, 1, piping, [0.0035] * len(piping), sides=6, capped=False)
        for x in (-1, 1):
            for z in (-1, 1):
                bottom = (x * 0.455, 0.018, z * 0.355)
                top = (x * 0.37, 0.45, z * 0.29)
                self.tube(part, 2, [bottom, top], [0.014, 0.020], sides=12)
                self.lathe(part, 3, (bottom[0], 0, bottom[2]),
                           [(0, 0), (0.016, 0), (0.019, 0.005),
                            (0.018, 0.019), (0, 0.023)], segments=10)

    def table(self):
        center = (-0.99, 0, 0.17)
        self.lathe('SideTable', 4, center,
                   [(0, 0.49), (0.245, 0.49), (0.268, 0.505), (0.27, 0.525),
                    (0.257, 0.54), (0, 0.54)])
        self.tube('SideTable', 2, [add(center, (0, 0.025, 0)),
                                  add(center, (0, 0.495, 0))], [0.025, 0.021], sides=16)
        self.lathe('SideTable', 2, center,
                   [(0, 0.002), (0.16, 0.002), (0.17, 0.012), (0.155, 0.027),
                    (0.045, 0.042), (0, 0.042)])

    def leaf(self, base, direction, length, width, variant):
        forward = unit(direction)
        side = unit(cross(forward, (0, 1, 0)))
        normal = unit(cross(side, forward))
        def point(t, u, face):
            envelope = max(0, math.sin(PI * t)) ** 0.7 * (1 - 0.18 * t)
            center = add(base, add(mul(forward, length * t),
                                  (0, 0.075 * math.sin(PI * t) - 0.075 * t * t, 0)))
            fold = 0.025 * envelope * (1 - abs(2 * u - 1))
            return add(center, add(mul(side, (u - 0.5) * width * envelope),
                                   mul(normal, fold + face * 0.0007)))
        mesh = self.mesh('PlanterAndPlant', 8 + variant)
        for face in (-1, 1):
            mesh.surface(lambda t, u: point(t, u, face), 14, 6,
                         lambda t, u: mul(normal, face))
        for u in (0.0, 1.0):
            mesh.surface(lambda t, v: point(t, u, 2 * v - 1), 14, 1,
                         lambda t, v: mul(side, -1 if u == 0 else 1))
        midrib = [point(i / 14, 0.5, 1) for i in range(14)]
        self.tube('PlanterAndPlant', 11, midrib,
                  [0.0018 * (1 - i / 16) for i in range(14)], sides=5)

    def plant(self):
        center = (1.06, 0, -0.19)
        self.lathe('PlanterAndPlant', 5, center,
                   [(0, 0), (0.178, 0), (0.195, 0.015), (0.205, 0.05),
                    (0.238, 0.47), (0.25, 0.515), (0.249, 0.535),
                    (0.24, 0.546), (0.229, 0.533), (0.225, 0.49),
                    (0.19, 0.09), (0, 0.09)], segments=64)
        self.lathe('PlanterAndPlant', 6, center, [(0.224, 0.49), (0, 0.49)])
        # Three gently bent stems, each carrying genuinely attached petioles.
        stems = [((-0.04, 0.49, 0), (-0.10, 1.02, 0.025), (-0.04, 1.68, 0.015)),
                 ((0.035, 0.49, 0.015), (0.15, 0.95, -0.035), (0.20, 1.46, -0.04)),
                 ((0, 0.49, -0.04), (-0.10, 0.82, -0.12), (-0.20, 1.23, -0.14))]
        for s, points in enumerate(stems):
            world = [add(center, p) for p in points]
            self.tube('PlanterAndPlant', 7, world, [0.014, 0.010, 0.004], sides=10)
            for i in range(5):
                t = 0.24 + i * 0.175
                a, b = (world[0], world[1]) if t < 0.5 else (world[1], world[2])
                local_t = t * 2 if t < 0.5 else (t - 0.5) * 2
                joint = add(a, mul(sub(b, a), local_t))
                angle = 0.55 + s * 1.8 + i * 2.40
                direction = (math.cos(angle), 0.34 + 0.10 * (i % 2), math.sin(angle))
                petiole_end = add(joint, mul(unit(direction), 0.09))
                self.tube('PlanterAndPlant', 7, [joint, petiole_end], [0.004, 0.0025], sides=7)
                self.leaf(petiole_end, direction, 0.40 + 0.055 * ((i + s) % 3),
                          0.24 + 0.035 * ((i + 2 * s) % 3), (i + s) % 3)

    def center_layout(self):
        positions = [p for mesh in self.parts.values() for p in mesh.positions]
        center = tuple((min(p[i] for p in positions) + max(p[i] for p in positions)) / 2
                       if i != 1 else 0 for i in range(3))
        self.chair_origin = mul(center, -1)
        for mesh in self.parts.values():
            mesh.positions = [sub(p, center) for p in mesh.positions]

    def write(self, output):
        document = {'asset': {'version': '2.0', 'generator': 'VRlizate generate_showcase_lounge.py',
                              'copyright': 'Original VRlizate asset; package license applies'},
                    'scene': 0, 'scenes': [{'name': 'Home Lounge', 'nodes': [0, 1, 2]}],
                    'nodes': [], 'meshes': [], 'materials': self.materials,
                    'accessors': [], 'bufferViews': [], 'buffers': [],
                    'extras': {'units': 'metres', 'up': '+Y', 'chairForward': '+Z',
                               'origin': 'assembly bounds centre on floor',
                               'chairFloorCenter': self.chair_origin, 'proceduralSeed': 'none'}}
        binary = bytearray()

        def accessor(values, kind, component=5126):
            while len(binary) % 4:
                binary.append(0)
            offset = len(binary)
            flat = [c for value in values for c in value]
            binary.extend(struct.pack('<' + ('f' if component == 5126 else 'I') * len(flat), *flat))
            view = len(document['bufferViews'])
            document['bufferViews'].append({'buffer': 0, 'byteOffset': offset,
                                           'byteLength': len(binary) - offset})
            entry = {'bufferView': view, 'componentType': component,
                     'count': len(values), 'type': kind}
            if kind == 'VEC3':
                entry['min'] = [min(v[i] for v in values) for i in range(3)]
                entry['max'] = [max(v[i] for v in values) for i in range(3)]
            document['accessors'].append(entry)
            return len(document['accessors']) - 1

        summary = {'generator': 'tool/generate_showcase_lounge.py', 'units': 'metres',
                   'up': '+Y', 'forward': '+Z', 'origin': 'assembly bounds centre on floor',
                   'chairFloorCenter': self.chair_origin, 'objects': {}, 'materials': len(self.materials)}
        all_positions = []
        for part in ['LoungeChair', 'SideTable', 'PlanterAndPlant']:
            primitives = []
            positions = []
            triangles = 0
            for (name, material), mesh in self.parts.items():
                if name != part:
                    continue
                primitives.append({'attributes': {'POSITION': accessor(mesh.positions, 'VEC3'),
                                                    'NORMAL': accessor(mesh.normals(), 'VEC3'),
                                                    'TEXCOORD_0': accessor(mesh.uvs, 'VEC2')},
                                   'indices': accessor([(i,) for face in mesh.triangles for i in face],
                                                       'SCALAR', 5125),
                                   'material': material, 'mode': 4})
                positions.extend(mesh.positions)
                triangles += len(mesh.triangles)
            index = len(document['meshes'])
            document['meshes'].append({'name': part, 'primitives': primitives})
            document['nodes'].append({'name': part, 'mesh': index})
            summary['objects'][part] = {'vertices': len(positions), 'triangles': triangles,
                                        'primitives': len(primitives), 'bounds': bounds(positions)}
            all_positions.extend(positions)
        document['buffers'] = [{'byteLength': len(binary)}]
        encoded = json.dumps(document, separators=(',', ':'), ensure_ascii=True).encode()
        encoded += b' ' * (-len(encoded) % 4)
        binary.extend(b'\0' * (-len(binary) % 4))
        result = (struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(binary)) +
                  struct.pack('<II', len(encoded), 0x4E4F534A) + encoded +
                  struct.pack('<II', len(binary), 0x004E4942) + binary)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(result)
        summary.update({'file': output.name, 'bytes': len(result),
                        'sha256': hashlib.sha256(result).hexdigest(), 'bounds': bounds(all_positions),
                        'triangles': sum(o['triangles'] for o in summary['objects'].values()),
                        'vertices': len(all_positions), 'textures': 0, 'animations': 0, 'skins': 0})
        output.with_suffix('.metadata.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(summary, indent=2))


def bounds(positions):
    return {'min': [round(min(p[i] for p in positions), 6) for i in range(3)],
            'max': [round(max(p[i] for p in positions), 6) for i in range(3)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path,
                        default=Path(__file__).resolve().parents[1] / 'assets/showcase/lounge.glb')
    args = parser.parse_args()
    lounge = Lounge()
    lounge.chair()
    lounge.table()
    lounge.plant()
    lounge.center_layout()
    lounge.write(args.output)


if __name__ == '__main__':
    main()
