import 'dart:io';
import 'dart:convert';
import 'package:solar_app/sems_client.dart';

Future<void> main() async {
  final client = SemsClient(email: 'daniel.forbes.96@hotmail.com', password: 'Goodwe2018');
  try {
    final today = DateTime.now();
    final date = '${today.year.toString().padLeft(4,'0')}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
    final result = await client.fetchPlantPowerChart('58faee60-cc86-4de8-ad3d-575dc3e8c01e', date);
    final out = File('plant_chart_result.json');
    await out.writeAsString(JsonEncoder.withIndent('  ').convert(result));
    print('Saved plant_chart_result.json');
  } catch (e, st) {
    print('Error: $e');
    print(st);
  }
}
