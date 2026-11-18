#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Convert static core glTF 2.0 triangle scenes to a bounded Darling model pack."""
import argparse
import base64
import io
import json
import math
from pathlib import Path
import struct
from urllib.parse import unquote

from PIL import Image

MAGIC = b"DMODEL1\0"
LIMIT = 512 * 1024 * 1024
COMPONENTS = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def item(values, index):
    if type(index) is not int or index < 0 or index >= len(values):
        raise ValueError("glTF array index out of bounds")
    return values[index]


def dot(a, b): return sum(x*y for x, y in zip(a, b))
def sub(a, b): return [x-y for x, y in zip(a, b)]
def cross(a, b): return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
def unit(a, fallback=(0, 1, 0)):
    length = math.sqrt(dot(a, a))
    return [v/length for v in a] if length > 1e-15 else list(fallback)


def multiply(a, b):
    return [sum(a[k*4+r]*b[c*4+k] for k in range(4)) for c in range(4) for r in range(4)]


IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def matrix(node):
    if "matrix" in node:
        value = node["matrix"]
        if len(value) != 16 or not all(math.isfinite(x) for x in value) or [value[i] for i in (3,7,11,15)] != [0,0,0,1]:
            raise ValueError("invalid node matrix")
        return value
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    sx, sy, sz = node.get("scale", [1, 1, 1])
    tx, ty, tz = node.get("translation", [0, 0, 0])
    if not all(math.isfinite(v) for v in (x,y,z,w,sx,sy,sz,tx,ty,tz)) or abs(x*x+y*y+z*z+w*w-1) > .001:
        raise ValueError("invalid node transform")
    return [(1-2*y*y-2*z*z)*sx, (2*x*y+2*z*w)*sx, (2*x*z-2*y*w)*sx, 0,
            (2*x*y-2*z*w)*sy, (1-2*x*x-2*z*z)*sy, (2*y*z+2*x*w)*sy, 0,
            (2*x*z+2*y*w)*sz, (2*y*z-2*x*w)*sz, (1-2*x*x-2*y*y)*sz, 0, tx, ty, tz, 1]


def point(m, p): return [sum(m[k*4+r]*p[k] for k in range(3))+m[12+r] for r in range(3)]
def direction(m, p): return [sum(m[k*4+r]*p[k] for k in range(3)) for r in range(3)]


def normal(m, n):
    # Cofactor columns give inverse-transpose, including nonuniform node scales.
    a, b, c = m[:3], m[4:7], m[8:11]
    cofactors = [cross(b, c), cross(c, a), cross(a, b)]
    determinant = dot(a, cofactors[0])
    if abs(determinant) < 1e-12:
        raise ValueError("singular mesh transform")
    return unit([sum(cofactors[k][r]*n[k] for k in range(3))/determinant for r in range(3)])


class Document:
    def __init__(self, path):
        self.root = path.resolve().parent
        raw = path.read_bytes()
        if len(raw) > LIMIT: raise ValueError("input exceeds size limit")
        binary = None
        if raw[:4] == b"glTF":
            if len(raw) < 20 or struct.unpack_from("<II", raw, 4) != (2, len(raw)):
                raise ValueError("invalid GLB header")
            offset, document = 12, None
            while offset < len(raw):
                if offset+8 > len(raw): raise ValueError("truncated GLB chunk")
                size, kind = struct.unpack_from("<II", raw, offset);offset += 8
                if size % 4 or size > len(raw)-offset: raise ValueError("invalid GLB chunk size")
                chunk = raw[offset:offset+size];offset += size
                if kind == 0x4e4f534a:
                    if document is not None: raise ValueError("duplicate GLB JSON")
                    document = json.loads(chunk)
                elif kind == 0x004e4942:
                    if binary is not None: raise ValueError("duplicate GLB binary chunk")
                    binary = chunk
            if document is None: raise ValueError("missing GLB JSON")
            self.g = document
        else:
            self.g = json.loads(raw)
        if self.g.get("asset", {}).get("version") != "2.0": raise ValueError("expected glTF 2.0")
        if self.g.get("extensionsRequired"): raise ValueError("required glTF extensions are not supported")
        self.buffers = []
        for b in self.g.get("buffers", []):
            data = self.uri(b["uri"]) if "uri" in b else binary
            if data is None or b["byteLength"] < 0 or b["byteLength"] > len(data):
                raise ValueError("missing or truncated buffer")
            self.buffers.append(data[:b["byteLength"]])
        if sum(map(len, self.buffers)) > LIMIT: raise ValueError("buffers exceed size limit")

    def uri(self, name):
        if name.startswith("data:"):
            header, payload = name.split(",", 1)
            if not header.endswith(";base64"): raise ValueError("only base64 data URIs are supported")
            data = base64.b64decode(payload, validate=True)
        else:
            path = (self.root / unquote(name)).resolve()
            if not path.is_relative_to(self.root) or ":" in name: raise ValueError("external URI escapes the asset folder")
            data = path.read_bytes()
        if len(data) > LIMIT: raise ValueError("resource exceeds size limit")
        return data

    def view(self, index):
        v = item(self.g["bufferViews"],index)
        b = item(self.buffers,v["buffer"]);offset = v.get("byteOffset", 0);length = v["byteLength"]
        if offset < 0 or length < 0 or offset+length > len(b): raise ValueError("bufferView out of bounds")
        return memoryview(b)[offset:offset+length], v

    def accessor(self, index, kind):
        a = item(self.g["accessors"],index)
        if a["type"] != kind or "sparse" in a: raise ValueError("unsupported accessor shape or sparse accessor")
        fmt, size = COMPONENTS[a["componentType"]];width = WIDTHS[kind];element = size*width
        data, view = self.view(a["bufferView"])
        stride = view.get("byteStride", element);offset = a.get("byteOffset", 0);count = a["count"]
        if count < 1 or count > 8_000_000 or stride < element or stride % size or offset < 0 or offset % size:
            raise ValueError("invalid accessor count, stride or offset")
        if offset+(count-1)*stride+element > len(data): raise ValueError("accessor out of bounds")
        result = [list(struct.unpack_from("<"+fmt*width, data, offset+i*stride)) for i in range(count)]
        if a.get("normalized"):
            if fmt in "bBhH":
                limit = {"b":127,"B":255,"h":32767,"H":65535}[fmt]
                result = [[max(-1, v/limit) for v in row] for row in result]
            else: raise ValueError("invalid normalized accessor")
        if not all(math.isfinite(x) for row in result for x in row): raise ValueError("non-finite accessor")
        return result

    def image(self, index):
        im = item(self.g["images"],index)
        return self.uri(im["uri"]) if "uri" in im else self.view(im["bufferView"])[0].tobytes()


def convert(source, output, texture_size=1024):
    doc = Document(source);g = doc.g
    vertices, indices, primitives, materials, textures = [], [], [], [], []
    images = {}

    def image(info):
        if not info: return 0xffffffff
        if info.get("texCoord", 0) or info.get("extensions"): raise ValueError("only untransformed TEXCOORD_0 textures are supported")
        index = item(g["textures"],info["index"])["source"]
        if index not in images:
            with Image.open(io.BytesIO(doc.image(index))) as im:
                if im.width > 8192 or im.height > 8192: raise ValueError("image dimensions exceed limit")
                im = im.convert("RGBA");im.thumbnail((texture_size, texture_size), Image.Resampling.LANCZOS)
                images[index] = len(textures);textures.append((im.width, im.height, im.tobytes()))
        return images[index]

    for m in g.get("materials", []) + [{}]:
        if m.get("alphaMode", "OPAQUE") != "OPAQUE": raise ValueError("this viewer supports opaque materials only")
        p = m.get("pbrMetallicRoughness", {});n = m.get("normalTexture", {});ao = m.get("occlusionTexture", {})
        factors = p.get("baseColorFactor", [1,1,1,1]) + [p.get("metallicFactor", 1), p.get("roughnessFactor", 1), n.get("scale", 1), ao.get("strength", 1)]
        factors += m.get("emissiveFactor", [0,0,0]) + [0]
        if len(factors) != 12 or not all(math.isfinite(v) for v in factors): raise ValueError("invalid material factors")
        if not 0 <= factors[4] <= 1 or not 0 <= factors[5] <= 1: raise ValueError("invalid metallic or roughness factor")
        materials.append((factors, [image(p.get("baseColorTexture")), image(n), image(p.get("metallicRoughnessTexture")), image(ao), image(m.get("emissiveTexture"))]))

    def mesh(index, transform):
        if len(primitives) > 4096: raise ValueError("too many mesh primitives")
        determinant = dot(transform[:3], cross(transform[4:7], transform[8:11]))
        for primitive in item(g["meshes"],index)["primitives"]:
            if primitive.get("mode", 4) != 4 or primitive.get("targets") or primitive.get("extensions"):
                raise ValueError("only uncompressed static TRIANGLES are supported")
            a = primitive["attributes"];positions = doc.accessor(a["POSITION"], "VEC3")
            count = len(positions)
            local = [v[0] for v in doc.accessor(primitive["indices"], "SCALAR")] if "indices" in primitive else list(range(count))
            if len(local) % 3 or not local or any(not isinstance(i, int) or i < 0 or i >= count for i in local):
                raise ValueError("invalid triangle indices")
            normals = doc.accessor(a["NORMAL"], "VEC3") if "NORMAL" in a else [[0,0,0] for _ in positions]
            uv = doc.accessor(a["TEXCOORD_0"], "VEC2") if "TEXCOORD_0" in a else [[0,0] for _ in positions]
            tangents = doc.accessor(a["TANGENT"], "VEC4") if "TANGENT" in a else None
            if any(len(x) != count for x in [normals, uv] + ([tangents] if tangents else [])):
                raise ValueError("vertex attribute counts disagree")
            if "NORMAL" not in a:
                # glTF requires flat face normals when NORMAL is absent. Split
                # shared corners so adjacent faces do not acquire smooth normals.
                positions = [positions[i] for i in local];uv = [uv[i] for i in local]
                if tangents: tangents = [tangents[i] for i in local]
                local = list(range(len(positions)));count = len(positions);normals = []
                for k in range(0, len(local), 3):
                    face = unit(cross(sub(positions[k+1],positions[k]),sub(positions[k+2],positions[k])))
                    normals.extend([face,face,face])
            positions = [point(transform, p) for p in positions]
            normals = [normal(transform, n) for n in normals]
            if tangents:
                tangents = [unit(direction(transform, t[:3])) + [t[3]*(-1 if determinant < 0 else 1)] for t in tangents]
            else:
                tan, bitan = [[0,0,0] for _ in positions], [[0,0,0] for _ in positions]
                for k in range(0, len(local), 3):
                    a0,b,c = local[k:k+3];p1,p2 = sub(positions[b],positions[a0]),sub(positions[c],positions[a0]);t1,t2 = sub(uv[b],uv[a0]),sub(uv[c],uv[a0])
                    divisor = t1[0]*t2[1]-t1[1]*t2[0]
                    if abs(divisor) < 1e-12: continue
                    t = [(p1[j]*t2[1]-p2[j]*t1[1])/divisor for j in range(3)]
                    bt = [(p2[j]*t1[0]-p1[j]*t2[0])/divisor for j in range(3)]
                    for i in (a0,b,c):
                        tan[i] = [x+y for x,y in zip(tan[i],t)];bitan[i] = [x+y for x,y in zip(bitan[i],bt)]
                tangents = []
                for n,t,bt in zip(normals,tan,bitan):
                    tangent = unit(sub(t,[dot(n,t)*v for v in n]), unit(cross(n,[0,0,1] if abs(n[2])<.9 else [0,1,0])))
                    tangents.append(tangent + [-1 if dot(cross(n,tangent),bt)<0 else 1])
            base = len(vertices);first = len(indices)
            vertices.extend([p+[1]+n+[0]+tuv+[0,0]+t for p,n,tuv,t in zip(positions,normals,uv,tangents)])
            indices.extend(base+i for i in local)
            mat = primitive.get("material", len(materials)-1)
            if mat < 0 or mat >= len(materials)-1 and "material" in primitive: raise ValueError("material index out of bounds")
            primitives.append((first,len(local),mat,0))

    def visit(index, parent, ancestors):
        if index in ancestors or len(ancestors) > 64: raise ValueError("cyclic or excessively deep node graph")
        node = item(g["nodes"],index)
        if "skin" in node or node.get("weights"): raise ValueError("skinned and morphed meshes are not supported")
        transform = multiply(parent,matrix(node))
        if "mesh" in node: mesh(node["mesh"],transform)
        for child in node.get("children", []): visit(child,transform,ancestors+(index,))

    for node in item(g["scenes"],g.get("scene",0)).get("nodes", []): visit(node,IDENTITY,())
    if not vertices: raise ValueError("scene has no triangle geometry")
    lower = [min(p[k] for p in vertices) for k in range(3)];upper = [max(p[k] for p in vertices) for k in range(3)]
    scale = max(upper[k]-lower[k] for k in range(3))
    if scale < 1e-12: raise ValueError("degenerate model bounds")
    center = [(x+y)*.5 for x,y in zip(lower,upper)]
    for vertex in vertices:
        for k in range(3): vertex[k] = (vertex[k]-center[k])*2/scale
        if not all(math.isfinite(v) for v in vertex): raise ValueError("non-finite transformed vertex")
    if len(vertices)>2_000_000 or len(indices)>12_000_000 or len(primitives)>4096 or len(materials)>1024 or len(textures)>128:
        raise ValueError("scene exceeds viewer resource limits")
    byte_size=28+len(vertices)*64+len(indices)*4+len(primitives)*16+len(materials)*68+sum(8+w*h*4 for w,h,_ in textures)
    if byte_size>LIMIT: raise ValueError("prepared model exceeds size limit")
    output.parent.mkdir(parents=True,exist_ok=True)
    with output.open("wb") as stream:
        stream.write(MAGIC+struct.pack("<5I",len(vertices),len(indices),len(primitives),len(materials),len(textures)))
        for vertex in vertices: stream.write(struct.pack("<16f",*vertex))
        stream.write(struct.pack("<"+"I"*len(indices),*indices))
        for primitive in primitives: stream.write(struct.pack("<4I",*primitive))
        for factors, slots in materials: stream.write(struct.pack("<12f5I",*factors,*slots))
        for width,height,data in textures: stream.write(struct.pack("<2I",width,height)+data)
    stats={"vertices":len(vertices),"triangles":len(indices)//3,"primitives":len(primitives),"materials":len(materials)-1,"textures":len(textures),"texture_max_size":texture_size,"bytes":output.stat().st_size,"source":source.name}
    output.with_suffix(".json").write_text(json.dumps(stats,indent=2)+"\n")
    return stats


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source",type=Path);parser.add_argument("-o","--output",required=True,type=Path)
    parser.add_argument("--texture-size",type=int,default=1024)
    args=parser.parse_args()
    if not 1 <= args.texture_size <= 2048: parser.error("texture-size must be between 1 and 2048")
    try: print(json.dumps(convert(args.source,args.output,args.texture_size),indent=2))
    except (ValueError,KeyError,IndexError,TypeError,OverflowError,OSError) as error: parser.exit(1,"Cannot prepare model: "+str(error)+"\n")
