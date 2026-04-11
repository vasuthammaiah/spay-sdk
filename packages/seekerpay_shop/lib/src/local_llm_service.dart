import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mrp_ai_reader.dart';
import 'mrp_data.dart';

class ModelFileStatus {
  final bool   exists;
  final int    sizeBytes;
  final String path;
  const ModelFileStatus({required this.exists, required this.sizeBytes, required this.path});
  bool get isValid => exists && sizeBytes > 100 * 1024 * 1024;
  String get sizeLabel {
    if (!exists) return 'Not found';
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }
}

void _log(String msg) => dev.log('[LocalLlm] $msg', name: 'seekerpay_shop');
void _logError(String msg, Object e, [StackTrace? st]) =>
    dev.log('[LocalLlm] ERROR: $msg\n$e', name: 'seekerpay_shop', error: e, stackTrace: st);

String _friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('No active inference model') || s.contains('not installed') || s.contains('Model not downloaded')) {
    return 'Model not downloaded. Go to Profile → Shop Configuration to download.';
  }
  return s;
}

class LocalLlmService {
  LocalLlmService._();
  static const _enabledKey    = 'spay_shop_llm_enabled';
  static const _modelFileName = 'gemma3-1b-it.task';
  static const _approxBytes   = 500 * 1024 * 1024;
  static const _minModelBytes = 100 * 1024 * 1024;
  static const _defaultModelUrl = 'https://drive.usercontent.google.com/download?id=1naDsVGLI0OM9McAh6hrHhnpP_4rtnhsD&export=download&confirm=t';
  static String? _customModelUrl;
  static String _country = 'India';

  static void configure({String? modelUrl, String? country}) {
    if (modelUrl != null) _customModelUrl = modelUrl;
    if (country != null) _country = country;
  }

  static InferenceModel? _model;
  static bool _initialized = false;

  static Future<void> init() async {
    try {
      await FlutterGemma.initialize().timeout(const Duration(seconds: 8), onTimeout: () => _log('FlutterGemma.initialize timed out'));
      _initialized = true;
      _log('FlutterGemma initialized');
    } catch (e, st) { _logError('FlutterGemma.initialize failed', e, st); }
  }

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_enabledKey, v);
  }

  static Future<File> _modelFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_modelFileName');
  }

  static Future<bool> _isValidModelFile(File file) async {
    try { return (await file.length()) > _minModelBytes; } catch (_) { return false; }
  }

  static Future<File?> _findOrAdoptModelFile() async {
    final dest = await _modelFile();
    if (await _isValidModelFile(dest)) return dest;
    final dirs = <Directory>[];
    try { dirs.add(await getApplicationSupportDirectory()); } catch (_) {}
    try { dirs.add(await getApplicationDocumentsDirectory()); } catch (_) {}
    try { dirs.add(await getTemporaryDirectory()); } catch (_) {}
    for (final dir in dirs) {
      if (!dir.existsSync()) continue;
      try {
        for (final file in dir.listSync(recursive: true).whereType<File>()) {
          if (!file.path.endsWith('.task')) continue;
          if (!await _isValidModelFile(file)) continue;
          if (file.path == dest.path) return dest;
          await dest.parent.create(recursive: true);
          try { await file.rename(dest.path); } catch (_) { await file.copy(dest.path); await file.delete(); }
          return dest;
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<bool> isModelDownloaded() async => await _findOrAdoptModelFile() != null;

  static Future<void> deleteModel() async {
    _model = null;
    try {
      final file = await _modelFile();
      if (await file.exists()) await file.delete();
      final p = await SharedPreferences.getInstance();
      await p.setBool(_enabledKey, false);
    } catch (_) {}
  }

  static Future<void> downloadModel({required void Function(double progress) onProgress}) async {
    final existing = await _findOrAdoptModelFile();
    if (existing != null) { onProgress(1.0); return; }
    final url  = _customModelUrl ?? _defaultModelUrl;
    final dir  = await getApplicationSupportDirectory();
    final dest = File('${dir.path}/$_modelFileName');
    await dest.parent.create(recursive: true);
    await _downloadWithProgress(url, dest, onProgress);
    final size = await dest.length();
    if (size < _minModelBytes) { await dest.delete(); throw Exception('Download too small — retry.'); }
    await FlutterGemma.installModel(modelType: ModelType.gemmaIt, fileType: ModelFileType.task).fromFile(dest.path).install();
  }

  static Future<void> _downloadWithProgress(String url, File dest, void Function(double) onProgress) async {
    final client = HttpClient();
    try {
      String downloadUrl = url; String? cookie;
      final req = await client.getUrl(Uri.parse(downloadUrl));
      req.followRedirects = false; req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Android 10)');
      var r = await req.close(); var hops = 0;
      while ((r.statusCode >= 301 && r.statusCode <= 307) && hops < 5) {
        final loc = r.headers.value(HttpHeaders.locationHeader); if (loc == null) break;
        await r.drain<void>();
        final setCookie = r.headers[HttpHeaders.setCookieHeader]; if (setCookie != null) cookie = setCookie.join('; ');
        final next = await client.getUrl(Uri.parse(loc));
        next.followRedirects = false; next.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Android 10)');
        if (cookie != null) next.headers.set(HttpHeaders.cookieHeader, cookie);
        r = await next.close(); hops++;
      }
      if (r.statusCode == 200) {
        final ct = r.headers.contentType?.mimeType ?? '';
        if (ct.contains('html')) {
          final cookieStr = r.headers[HttpHeaders.setCookieHeader]?.join('; ') ?? cookie ?? '';
          final match = RegExp(r'download_warning[^=]*=([^;]+)').firstMatch(cookieStr);
          if (match != null) downloadUrl = '$url&confirm=${match.group(1)}';
          await r.drain<void>();
        } else { await _streamResponse(r, dest, onProgress); return; }
      } else { await r.drain<void>(); throw Exception('HTTP ${r.statusCode}'); }
      final req2 = await client.getUrl(Uri.parse(downloadUrl));
      req2.followRedirects = true; req2.maxRedirects = 5;
      req2.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Android 10)');
      if (cookie != null) req2.headers.set(HttpHeaders.cookieHeader, cookie);
      final res2 = await req2.close();
      if (res2.statusCode != 200) throw Exception('HTTP ${res2.statusCode}');
      await _streamResponse(res2, dest, onProgress);
    } finally { client.close(); }
  }

  static Future<void> _streamResponse(HttpClientResponse r, File dest, void Function(double) onProgress) async {
    final total = r.contentLength; var received = 0;
    final sink = dest.openWrite();
    try {
      await for (final chunk in r) {
        sink.add(chunk); received += chunk.length;
        onProgress(total > 0 ? (received / total).clamp(0.0, 1.0) : (received / _approxBytes).clamp(0.0, 0.99));
      }
      await sink.flush();
    } finally { await sink.close(); }
    onProgress(1.0);
  }

  static String _getSystemPrompt(String country, {List<String>? focusFields}) {
    final context = country == 'Other' ? 'auto-detect the country' : 'the country is $country';
    final fieldsDesc = focusFields != null && focusFields.isNotEmpty 
      ? 'Return ONLY these fields: ${focusFields.join(", ")}.' 
      : 'Extract all available fields (productName, price, currency, expDate).';

    return '''
You read product label OCR text. $context. The input contains multiple OCR passes ([Pass 1], [Pass 2], etc.). 
Cross-reference ALL passes to find the correct information. If one pass is garbled, use the others.

RULES:
1. structure: Return ONLY valid JSON. No markdown, no explanation.
2. productName: Clean and recognizable. If text is 'Clean & Clear Morning Burst Face Wash with Cooling Menthol', return 'Clean & Clear Face Wash'.
3. price: Look for '${country == "India" ? "MRP" : "Price"}' or symbols like '\\\$'. Information may be split across lines (e.g., 'MRP' on line 1, '310' on line 2). Combine them.
4. expDate: Look for expiry dates. Fix common OCR errors (e.g., '09725' -> '09/25').
5. If a field is not found, return null.

$fieldsDesc
''';
  }

  static Future<(MrpData?, String)> extractFromTextWithOutput(String ocrText, {List<String>? focusFields}) async {
    InferenceModelSession? session;
    try {
      await _ensureModelLoaded();
      _log('RAW OCR DETECTED:\n' + ocrText);
      final sysPrompt = _getSystemPrompt(_country, focusFields: focusFields);
      dev.log('[Scanner] LLM System Prompt:\n$sysPrompt', name: 'seekerpay_shop');
      session = await _model!.createSession(temperature: 0.1, topK: 20, systemInstruction: sysPrompt);
      final truncated = ocrText.length > 800 ? ocrText.substring(0, 800) : ocrText;
      await session.addQueryChunk(Message(text: 'OCR Data:\n$truncated', isUser: true));
      final String raw = await session.getResponse();
      dev.log('[Scanner] LLM Output:\n$raw', name: 'seekerpay_shop');
      final parsed = _parseResponse(raw);
      return (parsed, raw);
    } catch (e, st) { _logError('extractFromText failed', e, st); return (null, _friendlyError(e)); }
    finally { if (session != null) { try { await session.close(); } catch (_) {} } }
  }

  static Future<ModelFileStatus> validateModelFile() async {
    final file = await _findOrAdoptModelFile() ?? await _modelFile();
    if (!await file.exists()) return ModelFileStatus(exists: false, sizeBytes: 0, path: file.path);
    final size = await file.length();
    return ModelFileStatus(exists: true, sizeBytes: size, path: file.path);
  }

  static bool get isModelLoaded => _model != null;
  static Future<(bool, String)> warmUp() async {
    try { await _ensureModelLoaded(); return (true, 'Engine ready on \$_lastBackend'); }
    catch (e) { return (false, _friendlyError(e)); }
  }

  static Future<void> autoStartIfEnabled() async {
    try {
      if (!await isEnabled()) return;
      if (_model != null) return;
      if (await _findOrAdoptModelFile() == null) return;
      await _ensureModelLoaded();
    } catch (e, st) { _logError('autoStartIfEnabled failed', e, st); }
  }

  static String _lastBackend = 'device';
  static String get lastBackend => _lastBackend;

  static Future<String> testLlm() async {
    InferenceModelSession? session;
    try {
      await _ensureModelLoaded();
      session = await _model!.createSession(temperature: 0.1, topK: 40, systemInstruction: 'You are a test agent. Reply ONLY with OK.');
      await session.addQueryChunk(const Message(text: 'Reply with only: OK', isUser: true));
      final result = await session.getResponse();
      return result.trim().isEmpty ? 'ERROR: empty response' : result.trim();
    } catch (e, st) { _logError('LLM test failed', e, st); return 'ERROR: \${_friendlyError(e)}'; }
    finally { if (session != null) { try { await session.close(); } catch (_) {} } }
  }

  static Future<void> _ensureModelLoaded() async {
    if (_model != null) return;
    if (!_initialized) { await FlutterGemma.initialize(); _initialized = true; }
    final file = await _findOrAdoptModelFile();
    if (file == null) throw StateError('Model not downloaded.');
    await FlutterGemma.installModel(modelType: ModelType.gemmaIt, fileType: ModelFileType.task).fromFile(file.path).install();
    for (final (backend, name) in [(PreferredBackend.gpu, 'GPU'), (PreferredBackend.cpu, 'CPU')]) {
      try {
        _model = await FlutterGemma.getActiveModel(maxTokens: 1024, preferredBackend: backend);
        _lastBackend = name; _log('Model loaded on \$name'); return;
      } catch (e) { _log('\$name failed: \$e'); }
    }
    throw StateError('Model failed to load on GPU and CPU.');
  }

  static MrpData? _parseResponse(String raw) {
    final clean = raw.replaceAll(RegExp(r'```(?:json)?', multiLine: true), '').replaceAll('`', '').trim();
    final d = _tryJson(clean); if (d != null) return d;
    final s = clean.indexOf('{'), e = clean.lastIndexOf('}');
    if (s != -1 && e > s) {
      final d2 = _tryJson(clean.substring(s, e + 1));
      if (d2 != null) return d2;
    }
    return _regexFallback(raw);
  }

  static MrpData? _tryJson(String text) {
    try { return _fromJson(jsonDecode(text) as Map<String, dynamic>); } catch (_) { return null; }
  }

  static MrpData? _regexFallback(String text) {
    String? str(String key) => RegExp('"\$key"\\\\s*:\\\\s*"([^"]+)"').firstMatch(text)?.group(1)?.trim();
    double? num(String key) { final m = RegExp('"\$key"\\\\s*:\\\\s*([\\\\d.]+)').firstMatch(text); return m != null ? double.tryParse(m.group(1)!) : null; }
    final price = num('price'); if (price == null && str('productName') == null) return null;
    String currency = 'USD';
    if (_country == 'India') currency = 'INR'; else if (_country == 'China') currency = 'CNY'; else if (_country == 'Japan') currency = 'JPY';
    return MrpData(productName: str('productName'), mrpAmount: price, currencyCode: currency, expDate: str('expDate') ?? str('expiryDate'), mfgDate: str('mfgDate'), quantity: str('quantity'), brand: str('brand'));
  }

  static MrpData _fromJson(Map<String, dynamic> j) {
    double? price; final pr = j['price'];
    if (pr is num) price = pr.toDouble(); else if (pr is String) price = double.tryParse(pr.replaceAll(',', ''));
    String defCurrency = 'USD';
    if (_country == 'India') defCurrency = 'INR'; else if (_country == 'China') defCurrency = 'CNY'; else if (_country == 'Japan') defCurrency = 'JPY';
    return MrpData(productName: _s(j['productName']), mrpAmount: price, currencyCode: _s(j['currency']) ?? defCurrency, quantity: _s(j['quantity']), brand: _s(j['brand']), mfgDate: _s(j['mfgDate']), expDate: _s(j['expDate']) ?? _s(j['expiryDate']), barcode: _s(j['barcode']));
  }

  static String? _s(dynamic v) { if (v == null || v == 'null') return null; final s = v.toString().trim(); return s.isEmpty ? null : s; }
}
