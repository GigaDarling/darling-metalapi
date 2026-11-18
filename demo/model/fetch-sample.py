#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fetch the CC0 Flight Helmet sample pinned by sample-assets.json."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination",required=True,type=Path)
    args=parser.parse_args();destination=args.destination.resolve()
    manifest=json.loads(Path(__file__).with_name("sample-assets.json").read_text())
    def fetch(entry):
        name,digest=entry;path=destination/name
        if path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest()==digest: return
        with urlopen(manifest["base_url"]+name,timeout=90) as response: data=response.read(64*1024*1024)
        if hashlib.sha256(data).hexdigest()!=digest: raise ValueError("sample checksum mismatch: "+name)
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
        print("Fetched",name,flush=True)
    with ThreadPoolExecutor(max_workers=4) as pool: list(pool.map(fetch,manifest["files"].items()))
    print("Verified CC0 Flight Helmet:",manifest["revision"],destination/"glTF/FlightHelmet.gltf")


if __name__=="__main__": main()
