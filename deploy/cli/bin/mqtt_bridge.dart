import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../lib/sems_client_cli.dart';

Future<int> main(List<String> args) async {
  final env = Platform.environment;
  final broker = args.isNotEmpty ? args[0] : env['MQTT_BROKER'] ?? 'localhost';
  final port = int.tryParse(env['MQTT_PORT'] ?? '') ?? 1883;
  final user = env['MQTT_USER'];
  final pass = env['MQTT_PASS'];
  final powerStationId = env['POWERSTATION_ID'] ?? (args.length > 1 ? args[1] : null);
  final intervalSec = int.tryParse(env['PUBLISH_INTERVAL_SEC'] ?? '') ?? 60;

  if (powerStationId == null) {
    print('Missing POWERSTATION_ID');
    return 2;
  }

  // quick test credentials, change as needed
  const email = 'daniel.forbes.96@hotmail.com';
  const password = 'Goodwe2018';

  final sems = SemsClientCli(email: email, password: password);

  final mqttClient = MqttServerClient(broker, 'sems_bridge_cli_${DateTime.now().millisecondsSinceEpoch}');
  mqttClient.port = port;
  mqttClient.logging(on: false);
  mqttClient.keepAlivePeriod = 20;
  mqttClient.autoReconnect = true;

  Future<bool> ensureConnected() async {
    if (mqttClient.connectionStatus?.state == MqttConnectionState.connected) return true;
    try {
      await mqttClient.connect();
      return mqttClient.connectionStatus?.state == MqttConnectionState.connected;
    } catch (_) {
      try { mqttClient.disconnect(); } catch (_) {}
      return false;
    }
  }

  // load persisted token file if present
  await sems.loadPersistedToken();

  var shouldStop = false;
  ProcessSignal.sigint.watch().listen((_) { shouldStop = true; });
  ProcessSignal.sigterm.watch().listen((_) { shouldStop = true; });

  while (!shouldStop) {
    final ok = await ensureConnected();
    if (!ok) {
      print('MQTT connect failed, retrying in 10s...');
      await Future.delayed(Duration(seconds: 10));
      continue;
    }

    try {
      final date = DateTime.now().toIso8601String().split('T').first;
      final chart = await sems.fetchPlantPowerChart(powerStationId, date);
      final payload = {
        'timestamp': DateTime.now().toIso8601String(),
        'current_pv_w': chart['current_pv_w'],
        'current_load_w': chart['current_load_w'],
        'today_kwh': chart['today_kwh'],
      };
      final jsonPayload = json.encode(payload);
      final topic = 'sems/inverter/$powerStationId/state';
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonPayload);
      mqttClient.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      print('Published to $topic: $jsonPayload');
    } catch (e, st) {
      print('Error during fetch/publish: $e\n$st');
    }

    var waited = 0;
    while (waited < intervalSec && !shouldStop) {
      await Future.delayed(Duration(seconds: 1));
      waited++;
    }
  }

  try { mqttClient.disconnect(); } catch (_) {}
  return 0;
}
