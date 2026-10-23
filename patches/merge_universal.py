#!/usr/bin/env python3
"""Merge base.apk + the arm64-v8a split into ONE installable universal APK.

base.apk holds code/resources (English default strings, all densities).
The arm64 split holds only native libs (+ manifest). Language/density splits
are dropped: base already contains unqualified English strings and every
density bucket, so nothing is lost for an English device.

IMPORTANT: base must come from a tree where apply_smali_patches.py has run —
it strips Play's split markers (requiredSplitTypes / isSplitRequired /
splitTypes) from AndroidManifest.xml. A base that still carries them installs
nowhere: PackageInstaller fails with INSTALL_FAILED_MISSING_SPLIT. Check with:
    aapt2 dump xmltree <merged.apk> --file AndroidManifest.xml | grep -i split

- All lib entries keep STORED compression (extractNativeLibs=false).
- Old v1 signature entries are stripped; re-sign afterwards (zipalign + apksigner).

Usage:
    python patches/merge_universal.py --base out/base.apk \
        --abi-split split_config.arm64_v8a.apk --dst universal.apk
"""
import argparse
import os
import zipfile

V1_SUFFIXES = (".SF", ".RSA", ".DSA", ".EC")
V1_EXACT = ("META-INF/MANIFEST.MF",)


def is_v1_sig(name: str) -> bool:
    if name in V1_EXACT:
        return True
    if name.startswith("META-INF/") and "/" not in name[len("META-INF/"):]:
        up = name.upper()
        return up.endswith(tuple(s.upper() for s in V1_SUFFIXES))
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--abi-split", required=True)
    ap.add_argument("--dst", required=True)
    args = ap.parse_args()

    zbase = zipfile.ZipFile(args.base)
    zabi = zipfile.ZipFile(args.abi_split)

    lib_entries = [i for i in zabi.infolist() if i.filename.startswith("lib/")]
    assert lib_entries, "no lib/ entries found in ABI split"
    stored = all(i.compress_type == zipfile.ZIP_STORED for i in lib_entries)
    print(f"ABI split: {len(lib_entries)} lib entries, all STORED={stored}")

    zout = zipfile.ZipFile(args.dst, "w", zipfile.ZIP_DEFLATED)
    written = stripped = 0
    for info in zbase.infolist():
        if is_v1_sig(info.filename):
            stripped += 1
            continue
        zout.writestr(info, zbase.read(info.filename), compress_type=info.compress_type)
        written += 1
    for info in lib_entries:
        assert info.filename not in zbase.namelist(), "lib collision: " + info.filename
        zout.writestr(info, zabi.read(info.filename), compress_type=info.compress_type)
        written += 1
    zout.close()
    zbase.close()
    zabi.close()

    # verify
    z = zipfile.ZipFile(args.dst)
    names = z.namelist()
    bad = z.testzip()
    libs = [n for n in names if n.startswith("lib/arm64-v8a/")]
    print(f"written: {args.dst}  entries={len(names)}  stripped_v1={stripped}")
    print(f"lib/arm64-v8a entries: {len(libs)}  sample: {libs[:3]}")
    print(f"crc check (testzip): {'FAIL ' + str(bad) if bad else 'OK'}")
    # confirm the signature-bypass constant survived the merge
    data = z.read("lib/arm64-v8a/libOKSMARTJIAMI.so")
    print("so patched constant present:",
          data.count(b"BD40CB13A568C953EC589D72239FC793") == 1)
    z.close()
    print("size:", os.path.getsize(args.dst))


if __name__ == "__main__":
    main()
