#!/usr/bin/env bash
set -euo pipefail

# Minimal installer for Raspberry Pi (Debian-based)
# Installs Dart, fetches project deps, and runs mqtt_bridge once for testing.

echo "Installing prerequisites..."
sudo apt update
sudo apt install -y apt-transport-https gnupg2 curl ca-certificates

if ! command -v dart >/dev/null 2>&1; then
  echo "Installing Dart SDK..."
  curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/dart.gpg
  echo "deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" | sudo tee /etc/apt/sources.list.d/dart_stable.list
  sudo apt update
  sudo apt install -y dart
else
  echo "Dart already installed: $(dart --version)"
fi

# Assume current dir is Solar/solar_app
if [ ! -f pubspec.yaml ]; then
  echo "Please run this script from the project 'solar_app' directory"
  exit 1
fi

echo "Fetching Dart packages..."
dart pub get

cat <<'EOF'

Installation complete. To test running the mqtt bridge once:

export MQTT_BROKER=192.168.1.10
export POWERSTATION_ID=58faee60-cc86-4de8-ad3d-575dc3e8c01e
export MQTT_PORT=1883

# then run
# dart run bin/mqtt_bridge.dart

EOF

# Optionally run once if user agrees
read -p "Run mqtt_bridge once now? (y/N) " runNow
if [[ "$runNow" =~ ^[Yy]$ ]]; then
  echo "Running mqtt_bridge..."
  dart run bin/mqtt_bridge.dart
fi
