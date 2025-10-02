import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class SemsClientCli {
  final String email;
  final String password;
  final http.Client _http;
  Map<String, dynamic>? _cachedTokenObj;
  String? _cachedTokenHeader;
  String? _cachedCookieHeader;
  DateTime? _loginTime;
  final File _tokenFile = File('sems_token.json');

  SemsClientCli({required this.email, required this.password, http.Client? httpClient}) : _http = httpClient ?? http.Client();

  Future<void> loadPersistedToken() async {
    if (await _tokenFile.exists()) {
      try {
        final s = await _tokenFile.readAsString();
        final m = json.decode(s) as Map<String, dynamic>;
        _cachedTokenObj = m['tokenObj'];
        _cachedTokenHeader = m['tokenHeader'];
        _cachedCookieHeader = m['cookieHeader'];
        if (m['loginTime'] != null) _loginTime = DateTime.parse(m['loginTime']);
      } catch (_) {}
    }
  }

  Future<void> _persistToken() async {
    final m = {
      'tokenObj': _cachedTokenObj,
      'tokenHeader': _cachedTokenHeader,
      'cookieHeader': _cachedCookieHeader,
      'loginTime': _loginTime?.toIso8601String(),
    };
    await _tokenFile.writeAsString(json.encode(m));
  }

  Future<void> _deletePersistedToken() async { if (await _tokenFile.exists()) await _tokenFile.delete(); }

  Future<void> _clearLoginCache() async { _cachedTokenObj = null; _cachedTokenHeader = null; _cachedCookieHeader = null; _loginTime = null; }

  Future<void> _ensureLogin() async {
    if (_cachedTokenHeader != null && _cachedCookieHeader != null) return;
    final loginUrl = Uri.parse('https://www.semsportal.com/home/login');
    final resp = await _http.post(loginUrl, body: {'account': email, 'pwd': password});
    if (resp.statusCode != 200) throw Exception('Login failed: ${resp.statusCode}');
    final jsonResp = json.decode(resp.body) as Map<String, dynamic>;
    final tokenObj = jsonResp['data']?['token'];
    if (tokenObj is Map<String, dynamic>) {
      _cachedTokenObj = tokenObj;
      _cachedTokenHeader = base64.encode(utf8.encode(json.encode(tokenObj)));
    }
    final setCookie = resp.headers['set-cookie'];
    if (setCookie != null) {
      final reg = RegExp(r'([A-Za-z0-9_\-]+=[^;,\s]+)');
      final cookiePairs = <String>[];
      for (final m in reg.allMatches(setCookie)) cookiePairs.add(m.group(1)!);
      if (cookiePairs.isNotEmpty) _cachedCookieHeader = cookiePairs.join('; ');
    }
    _loginTime = DateTime.now();
    await _persistToken();
  }

  Future<Map<String, dynamic>> fetchPlantPowerChart(String powerStationId, String date) async {
    await _ensureLogin();
    final url = Uri.parse('https://au.semsportal.com/api/v2/Charts/GetPlantPowerChart');
    final headers = {
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'Content-Type': 'application/json',
      'Origin': 'https://www.semsportal.com',
      'Referer': 'https://www.semsportal.com/',
    };
    if (_cachedTokenHeader != null) headers['token'] = _cachedTokenHeader!;
    if (_cachedCookieHeader != null) headers['cookie'] = _cachedCookieHeader!;
    final body = json.encode({'id': powerStationId, 'date': date, 'full_script': false});
    var resp = await _http.post(url, headers: headers, body: body);
    if (resp.statusCode != 200) throw Exception('PlantPowerChart request failed: ${resp.statusCode}');
    var j = json.decode(resp.body) as Map<String, dynamic>;
    if (j['code'] == 100002) {
      await _deletePersistedToken();
      await _clearLoginCache();
      await _ensureLogin();
      if (_cachedTokenHeader != null) headers['token'] = _cachedTokenHeader!;
      if (_cachedCookieHeader != null) headers['cookie'] = _cachedCookieHeader!;
      resp = await _http.post(url, headers: headers, body: body);
      if (resp.statusCode != 200) throw Exception('PlantPowerChart request failed: ${resp.statusCode}');
      j = json.decode(resp.body) as Map<String, dynamic>;
    }

    double todayKwh = 0.0;
    try {
      final gen = j['data']?['generateData'];
      if (gen is List) {
        for (final e in gen) {
          if (e is Map && (e['key']?.toString() == 'Generation' || e['key']?.toString().toLowerCase() == 'generation')) {
            todayKwh = double.tryParse(e['value'].toString()) ?? 0.0;
            break;
          }
        }
      }
    } catch (_) {}

    double currentPvW = 0.0;
    double currentLoadW = 0.0;
    try {
      final lines = j['data']?['lines'];
      if (lines is List) {
        for (final series in lines) {
          if (series is Map && series['key'] == 'PCurve_Power_PV') {
            final xy = series['xy'];
            if (xy is List) {
              for (var i = xy.length - 1; i >= 0; i--) {
                final v = xy[i]['y'];
                if (v != null) { currentPvW = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0; break; }
              }
            }
          }
          if (series is Map && series['key'] == 'PCurve_Power_Load') {
            final xy = series['xy'];
            if (xy is List) {
              for (var i = xy.length - 1; i >= 0; i--) {
                final v = xy[i]['y'];
                if (v != null) { currentLoadW = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0; break; }
              }
            }
          }
        }
      }
    } catch (_) {}

    return {'current_pv_w': currentPvW, 'current_load_w': currentLoadW, 'today_kwh': todayKwh, 'raw': j};
  }
}
