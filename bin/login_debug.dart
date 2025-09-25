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
    final out = {
      'status': r.statusCode,
      'headers': r.headers,
      'body_snippet': r.body.length > 4000 ? r.body.substring(0, 4000) + '\n...<<truncated>>' : r.body,
    };
    final f = File('login_debug.json');
    await f.writeAsString(JsonEncoder.withIndent('  ').convert(out));
    print('Wrote login_debug.json');
  } catch (e, st) {
    print('Error: $e');
    print(st);
  } finally {
    client.close();
  }
}
