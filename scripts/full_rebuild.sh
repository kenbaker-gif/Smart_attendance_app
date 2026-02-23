#!/bin/bash
echo "🏗️ Starting Big Rebuild (New Native Plugins)..."
flutter clean
flutter pub get  # ✅ Added this to fetch new packages automatically
shorebird release android --artifact apk
echo "✅ Done! Use 'flutter install' to put it on your S23 Ultra."