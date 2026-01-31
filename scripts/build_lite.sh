#!/bin/bash
# Move up one level to the project root where pubspec.yaml is
cd "$(dirname "$0")/.."

echo "Current Directory: $(pwd)"
echo "Cleaning old locks..."
rm -rf android/.gradle
rm -f android/local.properties

echo "Starting Light Build..."
# This is the fastest build command for low-RAM computers
flutter build apk --release --no-pub --no-tree-shake-icons