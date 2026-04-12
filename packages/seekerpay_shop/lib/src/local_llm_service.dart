import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mrp_data.dart';

class LocalLlmService {
  LocalLlmService._();
  static const _enabledKey    = 'spay_shop_llm_enabled';
  static const _modelFileName = 'gemma3-1b-it.task';
  static const _minModelBytes = 100 * 1024 * 1024;
  static String _country = 'India';

  static InferenceModel? _model;
  static bool _initialized = false;
  static String _lastBackend = 'device';
  static String get lastBackend => _lastBackend;

  static void configure({String? country}) {
    if (country != null) _country = country;
  }

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

  static Future<File?> _findOrAdoptModelFile() async {
    final dir = await getApplicationSupportDirectory();
    final dest = File('${dir.path}/$_modelFileName');
    if (await dest.exists() && (await dest.length()) > _minModelBytes) return dest;
    return null;
  }

  static Future<bool> isModelDownloaded() async => await _findOrAdoptModelFile() != null;

  static Future<ModelFileStatus> validateModelFile() async {
    final dir = await getApplicationSupportDirectory();
    final dest = File('${dir.path}/$_modelFileName');
    if (!await dest.exists()) return ModelFileStatus(exists: false, sizeBytes: 0, path: dest.path);
    final size = await dest.length();
    return ModelFileStatus(exists: true, sizeBytes: size, path: dest.path);
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
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$_modelFileName');
    if (await file.exists()) await file.delete();
  }

  static Future<void> downloadModel({required void Function(double progress) onProgress}) async {
    const url = 'https://drive.usercontent.google.com/download?id=1naDsVGLI0OM9McAh6hrHhnpP_4rtnhsD&export=download&confirm=t';
    final dir = await getApplicationSupportDirectory();
    final dest = File('${dir.path}/$_modelFileName');
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
    return '''Task: Extract product info.
Rules:
1. productName: Literal name. No labels.
2. price: Numeric total as STRING (e.g. "349.00"). PRESERVE DOT. 
3. expDate: MM/YY.
4. candidatePrices: Array of STRINGS of all prices found.
Output: {"productName":str,"price":str,"currency":"INR","expDate":str,"candidatePrices":[str]}''';
  }

  static Future<(MrpData?, String)> extractFromTextWithOutput(String ocrText) async {
    InferenceModelSession? session;
    try {
      await _ensureModelLoaded();
      print(' [LocalLlm] >>> RAW OCR SENT TO AI:\n$ocrText');
      session = await _model!.createSession(temperature: 0.2, topK: 20, systemInstruction: _getSystemPrompt());
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
      
      final rawPrice = j['price']?.toString() ?? '';
      final price = _cleanPrice(rawPrice);
      
      final cp = j['candidatePrices'];
      List<double> candidates = [];
      if (cp is List) {
        for (var item in cp) {
          final p = _cleanPrice(item.toString());
          if (p != null) candidates.add(p);
        }
      }

      return MrpData(
        productName: _s(j['productName']),
        mrpAmount: price,
        currencyCode: _s(j['currency']) ?? (_country == 'India' ? 'INR' : 'USD'),
        expDate: _s(j['expDate']),
        candidatePrices: candidates,
      );
    } catch (_) { return null; }
  }

  static double? _cleanPrice(String input) {
    final clean = input.replaceAll(RegExp(r'[^0-9.]'), '');
    double? val = double.tryParse(clean);
    if (val == null) return null;
    
    // Smart Correction: If price > 1000 and ends in 00/50/90 and has NO dot, 
    // it likely needs a decimal shift.
    if (val > 1000 && !input.contains('.')) {
      final s = val.toInt().toString();
      if (s.endsWith('00') || s.endsWith('50') || s.endsWith('90')) {
        val = val / 100.0;
      }
    }
    return val;
  }

  static String? _s(dynamic v) { if (v == null || v == 'null') return null; final s = v.toString().trim(); return s.isEmpty ? null : s; }
}

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
