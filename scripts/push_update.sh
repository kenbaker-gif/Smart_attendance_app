#!/bin/bash
echo "🔨 Building and pushing OTA patch..."
shorebird patch android
echo "✅ Patch published! Restart your S23 twice to see changes."