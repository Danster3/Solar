import 'dart:io';
import 'dart:convert';
import 'package:solar_app/sems_client.dart';

Future<void> main() async {
  final client = SemsClient(email: 'daniel.forbes.96@hotmail.com', password: 'Goodwe2018');
  try {
  // Login via separate http.Client to obtain token and cookie
    // use a temporary client
    final tempClient = HttpClient();
    final req = await tempClient.postUrl(Uri.parse('https://www.semsportal.com/home/login'));
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
    final body = 'account=${Uri.encodeComponent(client.email)}&pwd=${Uri.encodeComponent(client.password)}';
    req.write(body);
    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();
  tempClient.close(force: true);
    final map = json.decode(respBody) as Map<String, dynamic>;
    final tokenObj = map['data']?['token'];
    String? tokenHeader;
    if (tokenObj != null) {
      tokenHeader = base64.encode(utf8.encode(json.encode(tokenObj)));
    }
    final setCookieValues = resp.headers[HttpHeaders.setCookieHeader];
    String? cookieHeader;
    if (setCookieValues != null && setCookieValues.isNotEmpty) {
      final reg = RegExp(r'([A-Za-z0-9_\-]+=[^;,\s]+)');
      final pairs = <String>[];
      for (var v in setCookieValues) {
        for (final m in reg.allMatches(v)) pairs.add(m.group(1)!);
      }
      cookieHeader = pairs.join('; ');
    }

    final powerStationId = '58faee60-cc86-4de8-ad3d-575dc3e8c01e';
  final result = await client.fetchPowerflow(powerStationId, apiBase: 'https://au.semsportal.com/api/v2/', tokenHeader: tokenHeader, cookieHeader: cookieHeader);
    final out = File('sems_raw.json');
    await out.writeAsString(JsonEncoder.withIndent('  ').convert(result));
    print('Saved powerflow to sems_raw.json');
  } catch (e, st) {
    print('Error: $e');
    print(st);
  }
}
