# Deploying mqtt_bridge on Raspberry Pi

This folder contains helper files and instructions to run the `mqtt_bridge` on a Raspberry Pi.

Prerequisites
- Raspberry Pi OS (Debian-based) or other Debian-like distribution.
- Network access to your MQTT broker and SEMS endpoints.
- SSH access to the Pi (you already have this).

Two deployment options:
- Native Dart (recommended, lightweight)
- Docker (if your Pi supports it)

Quick native steps (one-shot)
```bash
# on the Pi (run as the pi user)
cd /home/pi
# clone or pull the repo
git clone https://github.com/Danster3/Solar.git || (cd Solar/solar_app && git pull)
cd Solar/solar_app
# run the installer script (this installs Dart and runs the bridge once)
sudo bash deploy/install_and_run_pi.sh
```

Manual (step-by-step)
1) Install Dart (Debian/Ubuntu):
```bash
sudo apt update
sudo apt install -y apt-transport-https gnupg2 curl ca-certificates
curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/dart.gpg
echo "deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" | sudo tee /etc/apt/sources.list.d/dart_stable.list
sudo apt update
sudo apt install -y dart
```
2) Run the bridge once to test:
```bash
cd /home/pi/Solar/solar_app
dart pub get
# configure environment variables (example)
export MQTT_BROKER=192.168.1.10
export POWERSTATION_ID=58faee60-cc86-4de8-ad3d-575dc3e8c01e
export MQTT_PORT=1883
dart run bin/mqtt_bridge.dart
```
3) Create systemd service (templates are in this folder):
```bash
sudo cp deploy/mqtt_bridge.service /etc/systemd/system/mqtt_bridge.service
sudo cp deploy/defaults.env /etc/default/mqtt_bridge
# edit /etc/default/mqtt_bridge to set your MQTT_BROKER, POWERSTATION_ID, etc.
sudo systemctl daemon-reload
sudo systemctl enable --now mqtt_bridge.service
sudo journalctl -u mqtt_bridge -f
```

Notes
- The CLI uses `sems_token.json` in the working directory for the token; the service sets WorkingDirectory to the repo directory so it will persist there. If you need to force re-login, delete that file and restart the service.
- If your Pi is ARMv6/v7/arm64 and the Dart package does not match, use Docker instead. See the Dockerfile in the project root or ask me to add one.

Files in this folder
- `install_and_run_pi.sh` — installer + quick test runner
- `mqtt_bridge.service` — systemd unit template
- `defaults.env` — environment variables template

If you want I can also:
- Add a Dockerfile tuned for Raspberry Pi (arm64/armv7) and a docker-compose example.
- Add a systemd unit that runs the Docker container.

