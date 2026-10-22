#!/usr/bin/env python3
"""Patch the signing-cert MD5 constant in libOKSMARTJIAMI.so inside a split APK.

Usage:
    python patches/patch_so.py --src split_config.arm64_v8a.apk \\
        --dst split_patched.arm64_v8a.apk \\
        --old-md5 64D33A12C0451837365F911F691D9334 \\
        --new-md5 BD40CB13A568C953EC589D72239FC793

The constant is 32 hex chars (16 bytes) in both cases, so the replacement is
in-place: the .so size and alignment do not change. The zip entry is rewritten
with a correct CRC (preserving STORED compression for the .so), then zipalign +
apksigner must be run on the result.
"""

import argparse
import os
import zipfile

SO_PATH = "lib/arm64-v8a/libOKSMARTJIAMI.so"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--dst", required=True)
    ap.add_argument("--old-md5", default="64D33A12C0451837365F911F691D9334")
    ap.add_argument("--new-md5", default="BD40CB13A568C953EC589D72239FC793")
    args = ap.parse_args()

    old = args.old_md5.encode("ascii")
    new = args.new_md5.encode("ascii")
    assert len(old) == 32 and len(new) == 32, "MD5 must be 32 hex chars"

    zin = zipfile.ZipFile(args.src)
    assert SO_PATH in zin.namelist(), SO_PATH + " not found in " + args.src
    so_data = zin.read(SO_PATH)
    assert so_data.count(old) == 1, (
        "expected exactly 1 occurrence of old constant, got %d" % so_data.count(old)
    )
    so_patched = so_data.replace(old, new)
    assert so_patched.count(new) == 1

    zout = zipfile.ZipFile(args.dst, "w", zipfile.ZIP_DEFLATED)
    for info in zin.infolist():
        data = so_patched if info.filename == SO_PATH else zin.read(info.filename)
        zout.writestr(info, data, compress_type=info.compress_type)
    zin.close()
    zout.close()

    # verify
    z = zipfile.ZipFile(args.dst)
    d = z.read(SO_PATH)
    stored = any(i.compress_type == zipfile.ZIP_STORED for i in z.infolist() if i.filename == SO_PATH)
    print("written:", args.dst, "size=", os.path.getsize(args.dst))
    print("old->new:", d.count(old), "->", d.count(new))
    print(".so compress_type stored:", stored)
    z.close()


if __name__ == "__main__":
    main()
