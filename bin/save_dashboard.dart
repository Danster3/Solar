import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final email = 'daniel.forbes.96@hotmail.com';
  final password = 'Goodwe2018';
  final loginUrl = Uri.parse('https://www.semsportal.com/home/login');
  final client = http.Client();
  try {
    final r = await client.post(loginUrl, body: {'account': email, 'pwd': password});
    if (r.statusCode != 200) {
      print('Login failed: ${r.statusCode}');
      return;
    }
    final jsonResp = json.decode(r.body) as Map<String, dynamic>;
    final redirect = jsonResp['data']?['redirect'];
    if (redirect == null) {
      print('No redirect in login response');
      return;
    }
    final dashUrl = Uri.parse('https://www.semsportal.com' + redirect);
    final dash = await client.get(dashUrl);
    if (dash.statusCode == 200) {
      final out = File('sems_dashboard.html');
      await out.writeAsString(dash.body);
      print('Saved dashboard to sems_dashboard.html');
    } else {
      print('Failed to fetch dashboard: ${dash.statusCode}');
    }
  } catch (e, st) {
    print('Error: $e');
    print(st);
  } finally {
    client.close();
  }
}
