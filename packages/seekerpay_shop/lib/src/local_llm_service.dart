import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class LocalLlmService {
  LocalLlmService._();
  static const _enabledKey    = 'spay_shop_llm_enabled';
  static const _modelFileName = 'gemma3-1b-it.task';
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
  static String _lastBackend = 'device';
  static String get lastBackend => _lastBackend;

  static Future<void> init() async {
    try {
      await FlutterGemma.initialize().timeout(const Duration(seconds: 8));
      _initialized = true;
    } catch (_) {}
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

  static Future<File?> _findOrAdoptModelFile() async {
    final dest = await _modelFile();
    if (await dest.exists() && (await dest.length()) > _minModelBytes) return dest;
    return null;
  }

  static Future<bool> isModelDownloaded() async => await _findOrAdoptModelFile() != null;

  static Future<ModelFileStatus> validateModelFile() async {
    final file = await _findOrAdoptModelFile() ?? await _modelFile();
    if (!await file.exists()) return ModelFileStatus(exists: false, sizeBytes: 0, path: file.path);
    final size = await file.length();
    return ModelFileStatus(exists: true, sizeBytes: size, path: file.path);
  }

  static bool get isModelLoaded => _model != null;

  static Future<(bool, String)> warmUp() async {
    try { await _ensureModelLoaded(); return (true, 'Engine ready on $_lastBackend'); }
    catch (e) { return (false, e.toString()); }
  }

  static Future<void> autoStartIfEnabled() async {
    if (!await isEnabled()) return;
    if (await isModelDownloaded()) await _ensureModelLoaded().catchError((_) {});
  }

  static Future<void> deleteModel() async {
    _model = null;
    final file = await _modelFile();
    if (await file.exists()) await file.delete();
  }

  static Future<void> downloadModel({required void Function(double progress) onProgress}) async {
    final url = _customModelUrl ?? _defaultModelUrl;
    final dest = await _modelFile();
    await dest.parent.create(recursive: true);
    
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final sink = dest.openWrite();
    int received = 0;
    int total = response.contentLength;
    
    await for (var chunk in response) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
    }
    await sink.close();
    client.close();
    
    await FlutterGemma.installModel(modelType: ModelType.gemmaIt, fileType: ModelFileType.task).fromFile(dest.path).install();
  }

  static String _getSystemPrompt() {
    return '''Task: Extract product JSON.
Rules:
1. productName: Literal name. No 'Corp'/'Ltd'.
2. price: Main total numeric price (no commas). IGNORE unit-rates.
3. currency: ISO (INR, USD).
4. expDate: MM/YY.
5. candidatePrices: Array of all potential total prices found.
Output: Valid JSON only {"productName":str,"price":num,"currency":str,"expDate":str,"candidatePrices":[num]}''';
  }

  static Future<(MrpData?, String)> extractFromTextWithOutput(String ocrText) async {
    InferenceModelSession? session;
    try {
      await _ensureModelLoaded();
      print(' [LocalLlm] >>> RAW OCR SENT TO AI:\n$ocrText');
      session = await _model!.createSession(temperature: 0.1, topK: 20, systemInstruction: _getSystemPrompt());
      await session.addQueryChunk(Message(text: ocrText, isUser: true));
      final String raw = await session.getResponse();
      print(' [LocalLlm] >>> AI RAW OUTPUT:\n$raw');
      return (_parseResponse(raw), raw);
    } catch (e) { return (null, e.toString()); }
    finally { if (session != null) await session.close(); }
  }

  static Future<void> _ensureModelLoaded() async {
    if (_model != null) return;
    if (!_initialized) { await FlutterGemma.initialize(); _initialized = true; }
    final file = await _findOrAdoptModelFile();
    if (file == null) throw StateError('Model not found');
    await FlutterGemma.installModel(modelType: ModelType.gemmaIt, fileType: ModelFileType.task).fromFile(file.path).install();
    try {
      _model = await FlutterGemma.getActiveModel(maxTokens: 512, preferredBackend: PreferredBackend.gpu);
      _lastBackend = 'GPU';
    } catch (_) {
      _model = await FlutterGemma.getActiveModel(maxTokens: 512, preferredBackend: PreferredBackend.cpu);
      _lastBackend = 'CPU';
    }
  }

  static MrpData? _parseResponse(String raw) {
    try {
      final s = raw.indexOf('{'), e = raw.lastIndexOf('}');
      if (s == -1 || e <= s) return null;
      final j = jsonDecode(raw.substring(s, e + 1)) as Map<String, dynamic>;
      final cp = j['candidatePrices'];
      List<double> candidates = [];
      if (cp is List) candidates = cp.map((e) => double.tryParse(e.toString()) ?? 0.0).where((e) => e > 0).toList();
      return MrpData(
        productName: _s(j['productName']),
        mrpAmount: double.tryParse(j['price']?.toString() ?? ''),
        currencyCode: _s(j['currency']) ?? (_country == 'India' ? 'INR' : 'USD'),
        expDate: _s(j['expDate']),
        candidatePrices: candidates,
      );
    } catch (_) { return null; }
  }

  static String? _s(dynamic v) { if (v == null || v == 'null') return null; final s = v.toString().trim(); return s.isEmpty ? null : s; }
}
