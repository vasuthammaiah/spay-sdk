import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'mrp_data.dart';
import 'mrp_parser.dart';

/// Reads product label text from an image using Claude Vision API.
class MrpAiReader {
  MrpAiReader._();

  static const _prefsKey = 'spay_anthropic_api_key';
  static const _enabledKey = 'spay_claude_enabled';
  static String? _apiKey;
  static String _country = 'India';
  static bool _enabled = true;

  static void configure({String? anthropicApiKey, String? country}) {
    if (anthropicApiKey != null) {
      _apiKey = anthropicApiKey.trim().isEmpty ? null : anthropicApiKey.trim();
    }
    if (country != null) _country = country;
  }

  static Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_prefsKey) ?? '';
    if (key.isNotEmpty) _apiKey = key;
    _enabled = prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> saveKey(String apiKey) async {
    final trimmed = apiKey.trim();
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) { await prefs.remove(_prefsKey); _apiKey = null; }
    else { await prefs.setString(_prefsKey, trimmed); _apiKey = trimmed; }
  }

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_enabledKey, v); _enabled = v;
  }

  static String? get activeKey => _apiKey;
  static bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;
  static bool get isEnabledSync => _enabled;

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-haiku-4-5-20251001';

  static String _getPrompt(String country, {List<String>? focusFields}) {
    final context = country == 'Other' ? 'auto-detect the country' : 'the country is $country';
    final fieldsDesc = focusFields != null && focusFields.isNotEmpty 
      ? 'Return ONLY these fields: ${focusFields.join(", ")}.' 
      : 'Extract all available fields.';

    return '''
You are reading a product label. $context. The input may contain OCR text alongside an image.
If multiple OCR passes are provided ([Pass 1], [Pass 2]), cross-reference them to find the most accurate data.

RULES:
1. struct: Return ONLY valid JSON. No markdown.
2. productName: Clean, recognizable name. Shorten marketing descriptions (e.g., 'Face Wash').
3. price: Look for local currency labels. Combine info split across lines.
4. expDate: Fix OCR errors (e.g., 'O8128' -> '08/28').
5. If a field is not found, return null.

$fieldsDesc
''';
  }

  static Future<MrpData> readFromImage(String imagePath, {List<String>? focusFields}) async {
    if (!isConfigured) throw StateError('Claude Vision not configured.');
    
    final sysPrompt = _getPrompt(_country, focusFields: focusFields);
    dev.log('[Scanner] Claude System Prompt:\n$sysPrompt', name: 'seekerpay_shop');

    final imageBytes = await _downscaleJpeg(imagePath, maxWidth: 2000);
    final base64Image = base64Encode(imageBytes);
    final body = jsonEncode({
      'model': _model, 'max_tokens': 1024,
      'messages': [
        {
          'role': 'user',
          'content': [
            { 'type': 'image', 'source': { 'type': 'base64', 'media_type': 'image/jpeg', 'data': base64Image } },
            { 'type': 'text', 'text': sysPrompt },
          ],
        },
      ],
    });
    final response = await http.post(Uri.parse(_endpoint), headers: { 'x-api-key': _apiKey!, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' }, body: body).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw HttpException('Claude API error ${response.statusCode}: ${response.body}');
    final responseData = jsonDecode(response.body) as Map<String, dynamic>;
    final content = (responseData['content'] as List).first;
    final text = (content['text'] as String).trim();
    
    dev.log('[Scanner] Claude Output:\n$text', name: 'seekerpay_shop');
    return _parseAiResponse(text);
  }

  static MrpData _parseAiResponse(String text) {
    final clean = text.replaceAll(RegExp(r'^\`\`\`(?:json)?\s*', multiLine: true), '').replaceAll(RegExp(r'\s*\`\`\`$', multiLine: true), '').trim();
    Map<String, dynamic> json;
    try { json = jsonDecode(clean) as Map<String, dynamic>; }
    catch (_) { final rawText = text.replaceAll(RegExp(r'[{}\[\]":]'), ' '); return MrpParser.parse(rawText); }
    double? price; final priceRaw = json['price'];
    if (priceRaw is num) price = priceRaw.toDouble(); else if (priceRaw is String) price = double.tryParse(priceRaw.replaceAll(',', ''));
    String? currency = json['currency'] as String?;
    if (currency != null) currency = _normaliseCurrencyCode(currency);
    if (currency == null && price != null) {
      if (_country == 'India') currency = 'INR'; else if (_country == 'China') currency = 'CNY'; else if (_country == 'Japan') currency = 'JPY';
      else currency = 'USD';
    }
    return MrpData(productName: _str(json['productName']), mrpAmount: price, currencyCode: currency, expDate: _str(json['expDate']), brand: _str(json['brand']), quantity: _str(json['quantity']), rawText: _str(json['rawText']), barcode: _str(json['barcode']));
  }

  static String? _str(dynamic v) { if (v == null || v == 'null') return null; final s = v.toString().trim(); return s.isEmpty ? null : s; }
  static String _normaliseCurrencyCode(String raw) {
    final map = { '₹': 'INR', 'rs': 'INR', 'rs.': 'INR', 'inr': 'INR', '\$': 'USD', 'usd': 'USD', '£': 'GBP', 'gbp': 'GBP', '€': 'EUR', 'eur': 'EUR', '¥': 'CNY', 'cny': 'CNY', 'jpy': 'JPY', 'rmb': 'CNY' };
    return map[raw.toLowerCase()] ?? raw.toUpperCase();
  }
  static Future<Uint8List> _downscaleJpeg(String imagePath, {int maxWidth = 2000}) async {
    final originalBytes = await File(imagePath).readAsBytes();
    if (originalBytes.lengthInBytes <= 3 * 1024 * 1024) return originalBytes;
    var decoded = img.decodeImage(originalBytes); if (decoded == null) return originalBytes;
    if (decoded.width > maxWidth) decoded = img.copyResize(decoded, width: maxWidth);
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 75));
  }
}
