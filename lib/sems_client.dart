import 'dart:convert';
// Token store: prefer Flutter secure storage; CLI falls back to file-based
import 'package:flutter_secure_storage/flutter_secure_storage.dart' show FlutterSecureStorage;
import 'token_store_file.dart' if (dart.library.io) 'token_store_file.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;

class SemsClient {
  final String email;
  final String password;
  final http.Client _http;

  // Cached authentication token and cookie to avoid logging in every request
  Map<String, dynamic>? _cachedTokenObj;
  String? _cachedTokenHeader;
  String? _cachedCookieHeader;
  DateTime? _loginTime;
  final FlutterSecureStorage? _secureStorage = _createSecureStorage();
  final TokenStoreImpl _fileStore = TokenStoreImpl();

  static FlutterSecureStorage? _createSecureStorage() {
    try {
      return const FlutterSecureStorage();
    } catch (_) {
      return null;
    }
  }

  SemsClient({required this.email, required this.password, http.Client? httpClient}) : _http = httpClient ?? http.Client();

  // load any persisted token from secure storage
  /// Load any persisted token from secure storage (used by Flutter app on startup).
  Future<void> _loadPersistedToken() async {
    String? s;
    if (_secureStorage != null) {
      s = await _secureStorage.read(key: 'sems_token');
    } else {
      s = await _fileStore.read();
    }
    if (s == null) return;
    try {
      final m = json.decode(s) as Map<String, dynamic>;
      _cachedTokenObj = m['tokenObj'];
      _cachedTokenHeader = m['tokenHeader'];
      _cachedCookieHeader = m['cookieHeader'];
      if (m['loginTime'] != null) _loginTime = DateTime.parse(m['loginTime']);
    } catch (_) {}
  }

  Future<void> _persistToken() async {
    final m = {
      'tokenObj': _cachedTokenObj,
      'tokenHeader': _cachedTokenHeader,
      'cookieHeader': _cachedCookieHeader,
      'loginTime': _loginTime?.toIso8601String(),
    };
    final encoded = json.encode(m);
    if (_secureStorage != null) {
      await _secureStorage.write(key: 'sems_token', value: encoded);
    } else {
      await _fileStore.write(encoded);
    }
  }

  Future<void> _deletePersistedToken() async {
    if (_secureStorage != null) {
      await _secureStorage.delete(key: 'sems_token');
    } else {
      await _fileStore.delete();
    }
  }

  /// Public helper for the Flutter app to pre-load any persisted token at startup.
  Future<void> loadPersistedTokenForApp() async {
    await _loadPersistedToken();
  }

  Future<void> _clearLoginCache() async {
    _cachedTokenObj = null;
    _cachedTokenHeader = null;
    _cachedCookieHeader = null;
    _loginTime = null;
  }

  Future<void> _ensureLogin() async {
  await _loadPersistedToken();
  if (_cachedTokenHeader != null && _cachedCookieHeader != null) return;
    final loginUrl = Uri.parse('https://www.semsportal.com/home/login');
    final resp = await _http.post(loginUrl, body: {'account': email, 'pwd': password});
    if (resp.statusCode != 200) {
      throw Exception('Login failed: ${resp.statusCode}');
    }
    Map<String, dynamic> jsonResp;
    try {
      jsonResp = json.decode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Unexpected login response');
    }
    final tokenObj = jsonResp['data']?['token'];
    if (tokenObj is Map<String, dynamic>) {
      _cachedTokenObj = tokenObj;
      _cachedTokenHeader = base64.encode(utf8.encode(json.encode(tokenObj)));
    }

    // extract cookies
    final setCookie = resp.headers['set-cookie'];
    if (setCookie != null) {
      final cookiePairs = <String>[];
      final reg = RegExp(r'([A-Za-z0-9_\-]+=[^;,\s]+)');
      for (final m in reg.allMatches(setCookie)) {
        cookiePairs.add(m.group(1)!);
      }
      if (cookiePairs.isNotEmpty) _cachedCookieHeader = cookiePairs.join('; ');
    }
    _loginTime = DateTime.now();
  await _persistToken();
  }

  /// Login and fetch dashboard HTML redirect, then parse embedded JS data
  Future<Map<String, dynamic>> fetchRealtime() async {
    // Note: SEMS portal expects a POST to /home/login with account/pwd as form fields
    final loginUrl = Uri.parse('https://www.semsportal.com/home/login');

  final resp = await _http.post(loginUrl, body: {'account': email, 'pwd': password});
    if (resp.statusCode != 200) {
      throw Exception('Login failed: ${resp.statusCode}');
    }

    // Response from SEMS contains JSON with data.redirect containing a URL path
    final bodyText = resp.body;
    Map<String, dynamic>? jsonResp;
    try {
      jsonResp = json.decode(bodyText) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Unexpected login response: not JSON');
    }

    final redirectPath = jsonResp['data']?['redirect'];
    final tokenObj = jsonResp['data']?['token'];
    String? loginToken;
    String? loginUid;
    String? loginVersion;
    if (tokenObj is Map<String, dynamic>) {
      loginToken = tokenObj['token']?.toString();
      loginUid = tokenObj['uid']?.toString();
      loginVersion = tokenObj['version']?.toString();
    }
    if (redirectPath == null) {
      throw Exception('Login response missing redirect');
    }

  final dashboardUrl = Uri.parse('https://www.semsportal.com' + redirectPath);
    // preserve cookies from login response
    // build a proper Cookie header from set-cookie values
    String? cookieHeader;
    final setCookie = resp.headers['set-cookie'];
    if (setCookie != null) {
      // Extract cookie name=value pairs using regex to avoid splitting inside attributes
      final cookiePairs = <String>[];
      final reg = RegExp(r'([A-Za-z0-9_\-]+=[^;,\s]+)');
      for (final m in reg.allMatches(setCookie)) {
        cookiePairs.add(m.group(1)!);
      }
      if (cookiePairs.isNotEmpty) cookieHeader = cookiePairs.join('; ');
    }
    final headers = {
      'referer': dashboardUrl.toString(),
      'accept': 'application/json, text/javascript, */*; q=0.01',
    };
    if (cookieHeader != null) headers['cookie'] = cookieHeader;
    final dashResp = await _http.get(dashboardUrl, headers: headers);
    if (dashResp.statusCode != 200) {
      throw Exception('Failed to load dashboard: ${dashResp.statusCode}');
    }

    final doc = parse(dashResp.body);

  // The page may embed a JS var with 'pw_info' that contains inverter JSON.
    final scripts = doc.getElementsByTagName('script');
    String? pwInfoJson;
    for (var s in scripts) {
      final content = s.text;
      if (content.contains('var pw_info =')) {
        final parts = content.split('var pw_info =');
        if (parts.length > 1) {
          final after = parts[1];
          // find the trailing semicolon
          final endIdx = after.indexOf(';');
          if (endIdx > 0) {
            pwInfoJson = after.substring(0, endIdx).trim();
            break;
          }
        }
      }
    }

    if (pwInfoJson == null) {
      // Try regional API fallback if the dashboard sets gops_api_domain
  final apiMatch = RegExp(r'gops_api_domain\s*=\s*"(https?://[^\"]+)"').firstMatch(dashResp.body);
  final apiBase = apiMatch?.group(1);
  // parse langVer if present from dashboard; fallback to components.langVer from earlier API error or loginVersion
  final langVerMatch = RegExp(r'langVer\s*=\s*\+?"?(\d+)"?').firstMatch(dashResp.body);
  var verParam = langVerMatch?.group(1) ?? '286';
      if (apiBase != null) {
        try {
          // Common endpoints seen in community projects
          // use detected verParam (from dashboard or fallback)
          final candidates = [
            Uri.parse(apiBase + 'Station/GetStationRealTimeData?ver=$verParam'),
            Uri.parse(apiBase + 'Inverter/GetInverterRealtimeData?ver=$verParam'),
            Uri.parse(apiBase + 'Station/GetStationOverview?ver=$verParam'),
          ];
          for (var url in candidates) {
            final r = await _http.get(url, headers: {
              ...headers,
              if (loginToken != null) 'token': loginToken,
              if (loginUid != null) 'uid': loginUid,
              if (loginVersion != null) 'version': loginVersion,
              if (cookieHeader != null) 'cookie': cookieHeader,
              'x-requested-with': 'XMLHttpRequest',
              'content-type': 'application/x-www-form-urlencoded; charset=UTF-8'
            });
            if (r.statusCode == 200) {
              try {
                final j = json.decode(r.body);
                if (j is Map<String, dynamic>) {
                  // If API returns an error with components.langVer, retry once with that ver
                  if (j['hasError'] == true && j['components'] is Map && j['components']['langVer'] != null) {
                    final newVer = j['components']['langVer'].toString();
                    if (newVer != verParam) {
                      verParam = newVer;
                      // retry endpoints with new ver
                      final retryCandidates = [
                        Uri.parse(apiBase + 'Station/GetStationRealTimeData?ver=$verParam'),
                        Uri.parse(apiBase + 'Inverter/GetInverterRealtimeData?ver=$verParam'),
                        Uri.parse(apiBase + 'Station/GetStationOverview?ver=$verParam'),
                      ];
                      for (var retryUrl in retryCandidates) {
                        final rr = await _http.get(retryUrl, headers: {
                          ...headers,
                          'x-requested-with': 'XMLHttpRequest',
                          'content-type': 'application/x-www-form-urlencoded; charset=UTF-8'
                        });
                        if (rr.statusCode == 200) {
                          try {
                            final jj = json.decode(rr.body);
                            if (jj is Map<String, dynamic> && jj['hasError'] != true) {
                              return {
                                'current_power_w': _toDouble(jj['data']?['pac'] ?? jj['data']?['PAC'] ?? 0),
                                'consumption_w': _toDouble(jj['data']?['consumption'] ?? 0),
                                'today_kwh': _toDouble(jj['data']?['today_energy'] ?? jj['data']?['E_D'] ?? 0),
                                'raw': jj,
                              };
                            }
                          } catch (_) {}
                        }
                      }
                    }
                  }
                  // attempt to extract a few common fields
                  double cur = 0, cons = 0, today = 0;
                  if (j.containsKey('data')) {
                    final d = j['data'];
                    if (d is Map<String, dynamic>) {
                      cur = _toDouble(d['pac'] ?? d['PAC'] ?? d['power'] ?? d['P_AC']);
                      today = _toDouble(d['today_energy'] ?? d['E_D'] ?? d['yield_today']);
                      cons = _toDouble(d['consumption'] ?? d['L_P'] ?? 0);
                    }
                  }
                  return {
                    'current_power_w': cur,
                    'consumption_w': cons,
                    'today_kwh': today,
                    'raw': j,
                  };
                }
              } catch (_) {}
            }
          }
          // If GET attempts failed, try POST with token/uid/version in JSON body
          if (loginToken != null || loginUid != null) {
            final postCandidates = [
              apiBase + 'Station/GetStationRealTimeData',
              apiBase + 'Inverter/GetInverterRealtimeData',
              apiBase + 'Station/GetStationOverview',
            ];
            final body = {
              if (loginUid != null) 'uid': loginUid,
              if (loginToken != null) 'token': loginToken,
              if (loginVersion != null) 'version': loginVersion,
              'ver': verParam,
            };
            for (var urlStr in postCandidates) {
              final url = Uri.parse(urlStr);
              try {
                final r = await _http.post(url, headers: {
                  ...headers,
                  'content-type': 'application/json; charset=UTF-8',
                }, body: json.encode(body));
                if (r.statusCode == 200) {
                  final j = json.decode(r.body);
                  if (j is Map<String, dynamic>) {
                    return {
                      'current_power_w': _toDouble(j['data']?['pac'] ?? j['data']?['PAC'] ?? 0),
                      'consumption_w': _toDouble(j['data']?['consumption'] ?? 0),
                      'today_kwh': _toDouble(j['data']?['today_energy'] ?? j['data']?['E_D'] ?? 0),
                      'raw': j,
                    };
                  }
                }
              } catch (_) {}
            }
          }
        } catch (_) {}
      }
      // collect some script samples for debugging to help adapt to different SEMS page structures
      final scripts = doc.getElementsByTagName('script');
      final samples = <String>[];
      for (var i = 0; i < scripts.length && i < 8; i++) {
        final t = scripts[i].text.trim();
        if (t.isEmpty) continue;
        samples.add(t.length > 800 ? t.substring(0, 800) + '...<<truncated>>' : t);
      }
      final sampleText = samples.join('\n---SCRIPT---\n');
  // try to detect regional API base for message
  final apiBaseForMsg = apiMatch?.group(1) ?? apiBase ?? 'unknown';
  final htmlSnippet = dashResp.body.length > 4000 ? dashResp.body.substring(0, 4000) + '\n...<<truncated>>' : dashResp.body;
  throw Exception('Unable to find pw_info JS variable. Detected apiBase: $apiBaseForMsg\nScript samples:\n$sampleText\n\nHTML snippet:\n$htmlSnippet');
    }

    final pwInfo = json.decode(pwInfoJson) as Map<String, dynamic>;

    // The structure contains inverter and station info. We try to extract common fields.
    final inverter = pwInfo['inverter']?[0]?['invert_full'] ?? {};

    // Common fields (may vary by firmware): PAC = current AC power (W), AC_POWER = sometimes used
    double currentPower = 0;
    double consumption = 0;
    double todayEnergy = 0;

    // current generation
    if (inverter.containsKey('PAC')) {
      currentPower = _toDouble(inverter['PAC']);
    } else if (inverter.containsKey('AC_Power')) {
      currentPower = _toDouble(inverter['AC_Power']);
    }

    // Try other common keys
    if (inverter.containsKey('E_D')) {
      todayEnergy = _toDouble(inverter['E_D']);
    } else if (pwInfo.containsKey('station') && pwInfo['station'].containsKey('today_energy')) {
      todayEnergy = _toDouble(pwInfo['station']['today_energy']);
    }

    // Consumption may not be available from inverter; attempt common key
    if (inverter.containsKey('L_P')) {
      consumption = _toDouble(inverter['L_P']);
    }

    return {
      'current_power_w': currentPower,
      'consumption_w': consumption,
      'today_kwh': todayEnergy,
      'raw': pwInfo,
    };
  }

  /// Call PowerStation/GetPowerflow with PowerStationId (matches user-provided cURL)
  Future<Map<String, dynamic>> fetchPowerflow(String powerStationId, {String? apiBase, String? tokenHeader, String? cookieHeader}) async {
    // determine apiBase if not supplied
    apiBase ??= 'https://au.semsportal.com/api/v2/';
    final url = Uri.parse(apiBase + 'PowerStation/GetPowerflow');
  await _ensureLogin();

  final headers = {
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'Origin': 'https://www.semsportal.com',
      'Referer': 'https://www.semsportal.com/',
      'User-Agent': 'Dart-Client',
      'neutral': '0',
      'x-requested-with': 'XMLHttpRequest',
    };
  if (tokenHeader != null) headers['token'] = tokenHeader; else if (_cachedTokenHeader != null) headers['token'] = _cachedTokenHeader!;
  if (cookieHeader != null) headers['cookie'] = cookieHeader; else if (_cachedCookieHeader != null) headers['cookie'] = _cachedCookieHeader!;

    final body = 'PowerStationId=$powerStationId';
    // make request and if authorization expired (code 100002) retry once after clearing cache
    var resp = await _http.post(url, headers: headers, body: body);
    if (resp.statusCode != 200) throw Exception('Powerflow request failed: ${resp.statusCode}');
    var j = json.decode(resp.body);
    if (j is Map<String, dynamic> && j['code'] == 100002) {
      // Token expired on server. Remove persisted token and force a fresh login.
      await _deletePersistedToken();
      await _clearLoginCache();
      await _ensureLogin();
      // update headers with refreshed values
      if (_cachedTokenHeader != null) headers['token'] = _cachedTokenHeader!;
      if (_cachedCookieHeader != null) headers['cookie'] = _cachedCookieHeader!;
      resp = await _http.post(url, headers: headers, body: body);
      if (resp.statusCode != 200) throw Exception('Powerflow request failed: ${resp.statusCode}');
      j = json.decode(resp.body);
    }
    if (j is Map<String, dynamic>) return j;
    return {'raw': resp.body};
  }

  /// Fetch today's plant power chart (generation/load series and totals)
  Future<Map<String, dynamic>> fetchPlantPowerChart(String powerStationId, String date, {bool debug = false}) async {
    // Use cached login when possible
    await _ensureLogin();
    final url = Uri.parse('https://au.semsportal.com/api/v2/Charts/GetPlantPowerChart');
    final headers = {
      'Accept': 'application/json, text/javascript, */*; q=0.01',
      'Content-Type': 'application/json',
      'Origin': 'https://www.semsportal.com',
      'Referer': 'https://www.semsportal.com/',
      'User-Agent': 'Dart-Client',
      'neutral': '0',
    };
    if (_cachedTokenHeader != null) headers['token'] = _cachedTokenHeader!;
    if (_cachedCookieHeader != null) headers['cookie'] = _cachedCookieHeader!;

    final body = json.encode({'id': powerStationId, 'date': date, 'full_script': false});
    var resp = await _http.post(url, headers: headers, body: body);
    if (resp.statusCode != 200) throw Exception('PlantPowerChart request failed: ${resp.statusCode}');
    var j = json.decode(resp.body) as Map<String, dynamic>;
    if (j['code'] == 100002) {
      // Token expired on server. Delete persisted token and force fresh login.
      await _deletePersistedToken();
      await _clearLoginCache();
      await _ensureLogin();
      if (_cachedTokenHeader != null) headers['token'] = _cachedTokenHeader!;
      if (_cachedCookieHeader != null) headers['cookie'] = _cachedCookieHeader!;
      resp = await _http.post(url, headers: headers, body: body);
      if (resp.statusCode != 200) throw Exception('PlantPowerChart request failed: ${resp.statusCode}');
      j = json.decode(resp.body) as Map<String, dynamic>;
    }

    if (debug) {
      try {
        final txt = json.encode(j);
        final truncated = txt.length > 2000 ? txt.substring(0, 2000) + '...<<truncated>>' : txt;
        print('[SEMS debug] PlantPowerChart raw: $truncated');
      } catch (e) {
        print('[SEMS debug] Failed to print raw: $e');
      }
    }

    // parse today's generation from generateData
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

    // parse latest PV and Load from lines series
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
                if (v != null) {
                  currentPvW = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
                  break;
                }
              }
            }
          }
          if (series is Map && series['key'] == 'PCurve_Power_Load') {
            final xy = series['xy'];
            if (xy is List) {
              for (var i = xy.length - 1; i >= 0; i--) {
                final v = xy[i]['y'];
                if (v != null) {
                  currentLoadW = (v is num) ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0;
                  break;
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    return {
      'current_pv_w': currentPvW,
      'current_load_w': currentLoadW,
      'today_kwh': todayKwh,
      'raw': j,
    };
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString();
    return double.tryParse(s) ?? 0.0;
  }
}
