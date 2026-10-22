# Signature bypass: `libOKSMARTJIAMI.so`

## What it is

`lib/arm64-v8a/libOKSMARTJIAMI.so` contains a hardcoded MD5 of the vendor's
signing certificate. At runtime the app compares it against the MD5 of the
certificate the APK is actually signed with. If they differ, the app refuses to
run (or crashes).

Because we re-sign with our own key (`okam.keystore`), the constants differ and
the check fails. We patch the constant in the `.so` instead of removing the
check — no code change, the `.so` stays stored and page-aligned.

## The two constants

- Vendor (original): `64D33A12C0451837365F911F691D9334`
- Mod (okam.keystore): `BD40CB13A568C953EC589D72239FC793`

Both are 32 hex chars (16 bytes) — identical length, so the replacement is
in-place and does not change the `.so` size or alignment.

## How to get your mod key's MD5

```powershell
keytool -list -v -keystore okam.keystore -alias okam 2>$null |
  Select-String "MD5"   # "MD5: BD:40:CB:13:...:93"
# strip the "MD5: " prefix and the colons, uppercase
```

## Why not just remove the check

The check is in native code (the `.so`), obfuscated. Finding and patching the
comparison instruction is fragile and version-dependent. Replacing the constant
is a 32-byte edit that survives most updates as long as the constant is still
there (and `patch_so.py` fails loudly if it is not).

## Constraints

- `extractNativeLibs=false` in the manifest: the `.so` must stay **stored**
  (uncompressed) and **4 KB aligned**. Never deflate it.
- The `.so` entry's CRC and v2/v3 signature digest must be regenerated after
  the byte edit. `patch_so.py` rewrites the zip entry (correct CRC) and then
  `zipalign` + `apksigner` re-sign. Editing bytes in place without re-signing
  gives `INSTALL_PARSE_FAILED_NO_CERTIFICATES`.
- If you lose `okam.keystore`, regenerate it and re-patch the constant with the
  new MD5. Old installs will not accept the new signature (Android forbids
  signature changes) — users must uninstall first.
