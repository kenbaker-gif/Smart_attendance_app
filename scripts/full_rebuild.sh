echo "🏗️ Starting Big Rebuild (New Native Plugins)..."
/root/.shorebird/bin/cache/flutter/1a55eb72b61a6c8acac0bf7f7d4738f399f83a0f/bin/flutter clean
/root/.shorebird/bin/cache/flutter/1a55eb72b61a6c8acac0bf7f7d4738f399f83a0f/bin/flutter pub get
shorebird release android --artifact aab
echo "✅ Done!"