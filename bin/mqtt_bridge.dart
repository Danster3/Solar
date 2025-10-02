import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:http/http.dart' as http;

import '../lib/sems_client.dart';

// Minimal MQTT bridge: fetch values and publish as JSON to topic
// Configuration via env vars or CLI args:
// MQTT_BROKER (host), MQTT_PORT (optional, default 1883), MQTT_USER, MQTT_PASS, MQTT_TOPIC (default "sems/inverter/<powerStationId>")

Future<int> main(List<String> args) async {
  final env = Platform.environment;
  final broker = args.isNotEmpty ? args[0] : env['MQTT_BROKER'] ?? 'localhost';
  final port = int.tryParse(env['MQTT_PORT'] ?? '') ?? 1883;
  final user = env['MQTT_USER'];
  final pass = env['MQTT_PASS'];
  final powerStationId = env['POWERSTATION_ID'] ?? (args.length > 1 ? args[1] : null);
  final topicBase = env['MQTT_TOPIC'] ?? (powerStationId != null ? 'sems/inverter/$powerStationId' : 'sems/inverter');
  final intervalSec = int.tryParse(env['PUBLISH_INTERVAL_SEC'] ?? '') ?? 60; // default 60s

  if (powerStationId == null) {
    print('Usage: dart run bin/mqtt_bridge.dart <broker> <powerStationId>');
    print('Or set environment variables MQTT_BROKER and POWERSTATION_ID');
    return 2;
  }

  // For quick testing your SEMS credentials may be hard-coded here (not recommended for production)
  const email = 'daniel.forbes.96@hotmail.com';
  const password = 'Goodwe2018';

  final client = SemsClient(email: email, password: password, httpClient: http.Client());

  // connect to MQTT
  final mqttClient = MqttServerClient(broker, 'sems_bridge_${DateTime.now().millisecondsSinceEpoch}');
  mqttClient.port = port;
  mqttClient.logging(on: false);
  mqttClient.keepAlivePeriod = 20;
  mqttClient.autoReconnect = true;
  mqttClient.onDisconnected = () => print('MQTT disconnected');

  if (user != null) {
    mqttClient.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('sems_bridge_${DateTime.now().millisecondsSinceEpoch}')
        .authenticateAs(user, pass ?? '')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
  }

  // Helper: ensure connected (tries to connect if disconnected)
  Future<bool> ensureConnected() async {
    if (mqttClient.connectionStatus?.state == MqttConnectionState.connected) return true;
    try {
      print('Connecting to MQTT $broker:$port ...');
      await mqttClient.connect();
      if (mqttClient.connectionStatus?.state == MqttConnectionState.connected) {
        print('MQTT connected');
        return true;
      }
      print('MQTT connection failed: ${mqttClient.connectionStatus}');
    } catch (e) {
      print('MQTT connect exception: $e');
    }
    try {
      mqttClient.disconnect();
    } catch (_) {}
    return false;
  }

  // load any persisted SEMS token once
  try {
    await client.loadPersistedTokenForApp();
  } catch (_) {}

  var shouldStop = false;
  // handle SIGINT/SIGTERM to shut down gracefully
  ProcessSignal.sigint.watch().listen((_) {
    print('Received SIGINT, shutting down...');
    shouldStop = true;
  });
  ProcessSignal.sigterm.watch().listen((_) {
    print('Received SIGTERM, shutting down...');
    shouldStop = true;
  });

  // Main loop: publish every intervalSec seconds
  while (!shouldStop) {
    final ok = await ensureConnected();
    if (!ok) {
      print('Failed to connect to MQTT, retrying in 10s...');
      await Future.delayed(Duration(seconds: 10));
      continue;
    }

    try {
      final date = DateTime.now().toIso8601String().split('T').first;
      final chart = await client.fetchPlantPowerChart(powerStationId, date);
      final payload = {
        'timestamp': DateTime.now().toIso8601String(),
        'current_pv_w': chart['current_pv_w'],
        'current_load_w': chart['current_load_w'],
        'today_kwh': chart['today_kwh'],
      };
      final jsonPayload = json.encode(payload);
      final topic = topicBase + '/state';
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonPayload);
      mqttClient.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      print('Published to $topic: $jsonPayload');
    } catch (e, st) {
      print('Failed to fetch/publish SEMS data: $e\n$st');
      // If auth expired or similar, the client will retry next loop when ensureConnected runs
    }

    // wait for the configured interval, but break early if stopping
    var waited = 0;
    while (waited < intervalSec && !shouldStop) {
      await Future.delayed(Duration(seconds: 1));
      waited++;
    }
  }

  print('Shutting down bridge...');
  try {
    mqttClient.disconnect();
  } catch (_) {}
  return 0;
}
