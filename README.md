# solar_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Project summary (work done)

This repository contains a small Flutter app and CLI tooling built to read GoodWe SEMS inverter data (current generation W, current consumption W, and total energy today kWh) and publish it to an MQTT broker for Home Assistant integration.

Key components implemented:
- `lib/sems_client.dart` — SEMS client that logs in, caches tokens, and fetches/parses API responses (supports dashboard HTML scraping fallback).
- `lib/token_store_file.dart` — file-backed token store used as a CLI fallback to `flutter_secure_storage`.
- `lib/main.dart` — Flutter UI wired to preload persisted token at startup and fetch inverter values.
- `bin/*.dart` — CLI test scripts used during development (`powerflow_test.dart`, `plant_chart_test.dart`) and a continuous MQTT bridge `bin/mqtt_bridge.dart`.
- `pubspec.yaml` — added `mqtt_client` dependency for the MQTT bridge.

MQTT bridge highlights (`bin/mqtt_bridge.dart`):
- Publishes inverter metrics to `sems/inverter/<POWERSTATION_ID>/state` as JSON.
- Configurable via environment variables (MQTT_BROKER, MQTT_PORT, MQTT_USER, MQTT_PASS, POWERSTATION_ID, PUBLISH_INTERVAL_SEC).
- Runs continuously, reconnects on disconnect, and handles graceful shutdown.

How to run the MQTT bridge (example):

```bash
export POWERSTATION_ID=58faee60-cc86-4de8-ad3d-575dc3e8c01e
export MQTT_BROKER=192.168.1.10
export MQTT_PORT=1883
export PUBLISH_INTERVAL_SEC=60
dart run bin/mqtt_bridge.dart
```

Notes and next steps:
- Replace the hard-coded SEMS credentials in the code before using in production.
- Windows desktop builds for `flutter_secure_storage` require Visual Studio C++ (ATL) components.
- Suggested follow-ups: add a README with Pi systemd unit, add a Dockerfile for ARM, publish Home Assistant MQTT sensor examples, or scaffold a HACS integration.

If you'd like any of the follow-ups implemented, open an issue or request it here and I can add the files and instructions.
