#!/usr/bin/env python3
"""Build-only fix for upstream flutter_inappwebview_android v1.1.3 + AGP 9.

Tracked upstream: https://github.com/pichillilorenzo/flutter_inappwebview/issues/2852
The published plugin references the removed proguard-android.txt rule set.
Replace precisely this call in the disposable pub cache, no other changes.
Remove this script when upstream releases a fixed stable package.
"""
from pathlib import Path
import os

home = Path(os.environ.get("PUB_CACHE", str(Path.home() / ".pub-cache")))
path = home / "hosted" / "pub.dev" / "flutter_inappwebview_android-1.1.3" / "android" / "build.gradle"
if not path.is_file():
    raise SystemExit(f"Expected WebView Android v1.1.3 was not resolved: {path}")
source = path.read_text()
old = "getDefaultProguardFile('proguard-android.txt')"
new = "getDefaultProguardFile('proguard-android-optimize.txt')"
count = source.count(old)
if count not in (1, 2):
    raise SystemExit(f"Unexpected flutter_inappwebview_android build.gradle contents ({count} legacy references)")
path.write_text(source.replace(old, new))
print(f"Patched {count} legacy ProGuard references for AGP 9 (ephemeral Flutter dependency cache).")
