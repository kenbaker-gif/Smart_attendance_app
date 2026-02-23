#!/bin/bash
echo "♻️ Checking for interrupted build..."
# Removes the lock file if it exists (common after a crash)
rm -f ../flutter/bin/cache/lockfile 2>/dev/null

echo "🚀 Resuming build..."
shorebird release android --artifact apk