import 'dart:io';
import 'dart:convert';
import 'package:solar_app/sems_client.dart';

Future<void> main() async {
  print('Starting SEMS live fetch test...');
  final client = SemsClient(email: 'daniel.forbes.96@hotmail.com', password: 'Goodwe2018');
  try {
    final data = await client.fetchRealtime();
    print('\n=== Parsed Result ===');
    print('Current power (W): \\${data['current_power_w']}');
    print('Consumption (W): \\${data['consumption_w']}');
    print('Today (kWh): \\${data['today_kwh']}');
    print('\n=== Raw pw_info (truncated) ===');
    final raw = data['raw'];
    // Save raw payload to sems_raw.json for inspection
    try {
      final out = File('sems_raw.json');
      await out.writeAsString(JsonEncoder.withIndent('  ').convert(raw));
      print('Saved raw payload to sems_raw.json');
    } catch (e) {
      print('Failed to save sems_raw.json: $e');
    }
  } catch (e, st) {
    print('Error during SEMS fetch: $e');
    print(st);
  }
}
