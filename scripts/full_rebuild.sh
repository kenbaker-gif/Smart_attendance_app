#!/bin/bash
echo "🏗️ Starting Big Rebuild (New Native Plugins)..."
/root/.shorebird/bin/cache/flutter/1a55eb72b61a6c8acac0bf7f7d4738f399f83a0f/bin/flutter clean
/root/.shorebird/bin/cache/flutter/1a55eb72b61a6c8acac0bf7f7d4738f399f83a0f/bin/flutter pub get  # ✅ Added this to fetch new packages automatically
shorebird release android --artifact apk
echo "✅ Done! Use '/root/.shorebird/bin/cache/flutter/1a55eb72b61a6c8acac0bf7f7d4738f399f83a0f/bin/flutter install' to put it on your S23 Ultra."