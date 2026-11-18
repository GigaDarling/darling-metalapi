#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic glTF contract tests; no external model or renderer is required."""
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

spec=importlib.util.spec_from_file_location("prepare_model",Path(__file__).with_name("prepare-model.py"))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        # Interleaved 16-byte POSITION records, then uint16 triangle indices.
        data=b"".join(struct.pack("<4f",*p,99) for p in [(0,0,0),(2,0,0),(0,2,0)])+struct.pack("<3H",0,1,2)
        (self.root/"mesh.bin").write_bytes(data)
        self.g={"asset":{"version":"2.0"},"buffers":[{"uri":"mesh.bin","byteLength":len(data)}],
            "bufferViews":[{"buffer":0,"byteLength":48,"byteStride":16},{"buffer":0,"byteOffset":48,"byteLength":6}],
            "accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},
                         {"bufferView":1,"componentType":5123,"count":3,"type":"SCALAR"}],
            "meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":1}]}],
            "nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]}

    def convert(self):
        path=self.root/"model.gltf";path.write_text(json.dumps(self.g))
        stats=module.convert(path,self.root/"output.dmodel",16)
        return stats,(self.root/"output.dmodel").read_bytes()

    def test_strided_uint16_and_missing_normals(self):
        stats,data=self.convert();self.assertEqual(stats["triangles"],1)
        self.assertEqual(data[:8],module.MAGIC)
        first=struct.unpack_from("<16f",data,28)
        self.assertEqual(first[:4],(-1,-1,0,1));self.assertEqual(first[4:7],(0,0,1))

    def test_node_instancing_and_transforms(self):
        self.g["nodes"]=[{"children":[1,2],"translation":[4,0,0]}, {"mesh":0}, {"mesh":0,"translation":[0,0,3]}]
        stats,data=self.convert();self.assertEqual(stats["vertices"],6);self.assertEqual(stats["triangles"],2)
        first=struct.unpack_from("<3f",data,28);second=struct.unpack_from("<3f",data,28+3*64)
        self.assertAlmostEqual(second[2]-first[2],2)

    def test_inverse_transpose_normal(self):
        m=module.matrix({"scale":[2,1,1]});n=module.normal(m,[1,1,0])
        self.assertAlmostEqual(n[1]/n[0],2)

    def test_glb_binary_chunk(self):
        binary=(self.root/"mesh.bin").read_bytes();del self.g["buffers"][0]["uri"]
        document=json.dumps(self.g).encode();document+=b" "*((-len(document))%4)
        binary+=b"\0"*((-len(binary))%4)
        chunks=struct.pack("<II",len(document),0x4e4f534a)+document+struct.pack("<II",len(binary),0x004e4942)+binary
        path=self.root/"sample.glb";path.write_bytes(b"glTF"+struct.pack("<II",2,12+len(chunks))+chunks)
        stats=module.convert(path,self.root/"sample.dmodel",16);self.assertEqual(stats["triangles"],1)

    def test_quaternion_rotation(self):
        import math
        m=module.matrix({"rotation":[0,0,math.sqrt(.5),math.sqrt(.5)]})
        p=module.point(m,[1,0,0]);self.assertAlmostEqual(p[0],0);self.assertAlmostEqual(p[1],1)

    def test_truncated_accessor(self):
        self.g["accessors"][0]["count"]=4
        with self.assertRaisesRegex(ValueError,"out of bounds"): self.convert()

    def test_negative_index(self):
        self.g["meshes"][0]["primitives"][0]["attributes"]["POSITION"]=-1
        with self.assertRaisesRegex(ValueError,"index out of bounds"): self.convert()

    def test_out_of_range_triangle(self):
        path=self.root/"mesh.bin";path.write_bytes(path.read_bytes()[:-2]+struct.pack("<H",3))
        with self.assertRaisesRegex(ValueError,"triangle indices"): self.convert()

    def test_cycle(self):
        self.g["nodes"][0]["children"]=[0]
        with self.assertRaisesRegex(ValueError,"cyclic"): self.convert()

    def test_directory_escape(self):
        self.g["buffers"][0]["uri"]="../outside.bin"
        with self.assertRaisesRegex(ValueError,"escapes"): self.convert()

    def test_required_extension(self):
        self.g["extensionsRequired"]=["KHR_draco_mesh_compression"]
        with self.assertRaisesRegex(ValueError,"required glTF extensions"): self.convert()

    def test_bad_primitive_mode(self):
        self.g["meshes"][0]["primitives"][0]["mode"]=1
        with self.assertRaisesRegex(ValueError,"TRIANGLES"): self.convert()

    def test_projective_node(self):
        self.g["nodes"][0]["matrix"]=list(module.IDENTITY);self.g["nodes"][0]["matrix"][3]=1
        with self.assertRaisesRegex(ValueError,"invalid node matrix"): self.convert()

    def test_unsupported_transparency(self):
        self.g["materials"]=[{"alphaMode":"BLEND"}]
        with self.assertRaisesRegex(ValueError,"opaque"): self.convert()


if __name__=="__main__": unittest.main()
