#!/usr/bin/env python3
"""Idempotent smali patcher for the O-KAM Pro ad-free build.

Usage:
    python patches/apply_smali_patches.py --tree apktool

Each patch is (file, old, new, required). If `new` is already present the
patch is skipped (already applied). If `old` is missing AND `new` is missing:
  - required patch -> fail loudly (version drift; update the anchor, do not
    weaken it).
  - optional patch -> skip (probe cleanup on a tree that never had probes).
"""

import argparse
import os
import sys

PATCHES = [
    (
        "smali_classes4/com/okampro/oksmart/MainActivity$a.smali",
        """    const-string p2, "userId"

    .line 3
    invoke-virtual {p1, p2}, Lk7/j;->a(Ljava/lang/String;)Ljava/lang/Object;

    move-result-object p1

    check-cast p1, Ljava/lang/String;

    .line 4
    new-instance v0, Ljava/lang/StringBuilder;

    invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V

    const-string v2, "userId: "

    invoke-virtual {v0, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;

    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;

    move-result-object v0

    invoke-static {v1, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;)I

    .line 5
    new-instance v0, Landroid/content/Intent;

    iget-object v1, p0, Lcom/okampro/oksmart/MainActivity$a;->a:Lcom/okampro/oksmart/MainActivity;

    const-class v2, Lcom/okampro/oksmart/SplashAdActivity;

    invoke-direct {v0, v1, v2}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V

    .line 6
    invoke-virtual {v0, p2, p1}, Landroid/content/Intent;->putExtra(Ljava/lang/String;Ljava/lang/String;)Landroid/content/Intent;

    const/high16 p1, 0x10000000

    .line 7
    invoke-virtual {v0, p1}, Landroid/content/Intent;->setFlags(I)Landroid/content/Intent;

    .line 8
    iget-object p1, p0, Lcom/okampro/oksmart/MainActivity$a;->a:Lcom/okampro/oksmart/MainActivity;

    invoke-virtual {p1, v0}, Landroid/app/Activity;->startActivity(Landroid/content/Intent;)V

    goto/16 :goto_0
""",
        """    # --- ad-block patch: never open the fullscreen splash-ad activity ---
    # Dart calls jumpToActivity fire-and-forget and never waits for a reply,
    # so returning immediately is safe.
    return-void
""",
        True,
    ),
    (
        "smali_classes4/com/secmtp/sdk/core/api/ATSDK.smali",
        """    invoke-static {}, Lcom/secmtp/sdk/core/common/wn/wwm;->wv()Lcom/secmtp/sdk/core/common/wn/wwm;

    move-result-object v0

    invoke-virtual {v0, p0, p1, p2, p3}, Lcom/secmtp/sdk/core/common/wn/wwm;->ww(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;Lcom/secmtp/sdk/core/api/ATNetworkConfig;)V
""",
        """    # --- ad-block patch: skip wwm.wv().ww(...) so no placement config is fetched ---
""",
        True,
    ),
    (
        "smali_classes4/com/secmtp/sdk/core/api/ATAdStatusInfo.smali",
        """    iget-boolean v0, p0, Lcom/secmtp/sdk/core/api/ATAdStatusInfo;->mIsReady:Z

    return v0
""",
        """    # --- ad-block patch: an ad is never "ready", so the Dart layer never shows one ---
    const/4 v0, 0x0

    return v0
""",
        True,
    ),
    (
        "smali_classes4/k5/c.smali",
        ".method public e()Z\n    .locals 3\n\n",
        ".method public e()Z\n    .locals 3\n\n    # --- ad-block patch: the Dart native-ad widget busy-polls this in a while() loop.\n    # Report \"ready\" so the poll terminates; the view we hand it is empty (see i()).\n    const/4 v0, 0x1\n\n    return v0\n\n",
        True,
    ),
    (
        "smali_classes4/k5/c.smali",
        """    invoke-virtual {p1}, Lcom/secmtp/sdk/nativead/api/ATNative;->makeAdRequest()V
""",
        """    # --- ad-block patch: never request an ad creative from the network ---
""",
        True,
    ),
    (
        "smali_classes4/k5/c.smali",
        """    .line 1
    iget-object v0, p0, Lk5/c;->b:Lcom/secmtp/sdk/nativead/api/ATNative;
""",
        """    # --- ad-block patch: always hand Flutter an empty (non-null) native ad view.
    # Non-null is required: returning null makes the Dart widget spin at ~160% CPU.
    new-instance v0, Lcom/secmtp/sdk/nativead/api/ATNativeAdView;

    iget-object v1, p0, Lk5/c;->h:Landroid/app/Activity;

    invoke-direct {v0, v1}, Lcom/secmtp/sdk/nativead/api/ATNativeAdView;-><init>(Landroid/content/Context;)V

    return-object v0

    .line 1
    iget-object v0, p0, Lk5/c;->b:Lcom/secmtp/sdk/nativead/api/ATNative;
""",
        True,
    ),
    # Optional probe cleanup (only needed on trees that had debug probes)
    (
        "smali_classes4/com/secmtp/sdk/core/api/ATSDK.smali",
        """    const-string v0, "MODPROBE_SDK"
""",
        """    # --- ad-block patch: never bootstrap the ad SDK ---
""",
        False,
    ),
    (
        "smali_classes4/com/secmtp/sdk/core/common/wn/wwm.smali",
        """    const-string v0, "MODPROBE_SDK"
""",
        """    # probe removed
""",
        False,
    ),
    (
        "smali_classes5/com/secmtp/sdk/mediation/adapters/admob/AdMobInitManager.smali",
        """    const-string v0, "MODPROBE_SDK"
""",
        """    # probe removed
""",
        False,
    ),
]


def apply(tree, rel, old, new, required):
    path = os.path.join(tree, rel)
    if not os.path.exists(path):
        print("MISSING FILE:", path)
        return False
    src = open(path, encoding="utf-8").read()
    if new in src:
        print("already patched:", rel)
        return True
    if old not in src:
        if required:
            print("ANCHOR NOT FOUND (version drift?):", rel)
            print("  old snippet:", repr(old[:80]))
            return False
        print("optional anchor absent, skipping:", rel)
        return True
    src = src.replace(old, new, 1)
    open(path, "w", encoding="utf-8", newline="").write(src)
    print("patched:", rel)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tree", default="apktool")
    args = ap.parse_args()
    ok = True
    for rel, old, new, required in PATCHES:
        if not apply(args.tree, rel, old, new, required):
            ok = False
    if not ok:
        sys.exit(1)
    print("all required patches applied")


if __name__ == "__main__":
    main()
