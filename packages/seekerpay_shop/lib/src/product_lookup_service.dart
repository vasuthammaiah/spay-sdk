import 'dart:convert';
import 'package:http/http.dart' as http;
import 'product_model.dart';

/// Looks up a product by barcode using multiple sources:
/// 1. Open Food Facts (food products, global)
/// 2. Open Beauty Facts (cosmetics/personal care)
/// 3. ean-search.org (1B+ products, good Indian coverage — needs free API key)
/// 4. GS1 company prefix fallback (identifies brand from barcode prefix, no API needed)
class ProductLookupService {
  static const _foodApiBase = 'https://world.openfoodfacts.org/api/v0/product';
  static const _beautyApiBase = 'https://world.openbeautyfacts.org/api/v0/product';
  static const _userAgent = 'SeekerPay/1.0 (contact@seekerpay.com)';

  /// Optional ean-search.org API key.
  /// Register free at https://www.ean-search.org/register — 100 lookups/day.
  final String? eanSearchApiKey;

  const ProductLookupService({this.eanSearchApiKey});

  Future<Product?> lookup(String barcode) async {
    final cleaned = barcode.trim();
    if (cleaned.isEmpty) return null;

    // 1. Open Food Facts
    final fromFood = await _fetchOpenFacts(_foodApiBase, cleaned);
    if (fromFood != null) return fromFood;

    // 2. Open Beauty Facts (cosmetics / personal care)
    final fromBeauty = await _fetchOpenFacts(_beautyApiBase, cleaned);
    if (fromBeauty != null) return fromBeauty;

    // 3. ean-search.org (needs API key — best coverage for Indian products)
    if (eanSearchApiKey != null && eanSearchApiKey!.isNotEmpty) {
      final fromEan = await _fetchEanSearch(cleaned);
      if (fromEan != null) return fromEan;
    }

    // 4. GS1 prefix fallback — identifies company/brand without any API
    return _gs1FallbackProduct(cleaned);
  }

  // ── Open Food / Beauty Facts ──────────────────────────────────────────────

  Future<Product?> _fetchOpenFacts(String base, String barcode) async {
    try {
      final uri = Uri.parse('$base/$barcode.json');
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] != 1) return null;

      final p = json['product'] as Map<String, dynamic>? ?? {};
      final name =
          (p['product_name_en'] as String? ?? p['product_name'] as String? ?? '')
              .trim();
      final brand = (p['brands'] as String? ?? '').split(',').first.trim();
      if (name.isEmpty && brand.isEmpty) return null;

      final rawCategory = p['categories'] as String? ?? '';
      final category =
          rawCategory.isNotEmpty ? rawCategory.split(',').last.trim() : null;

      return Product(
        barcode: barcode,
        name: name.isNotEmpty ? name : brand,
        brand: brand,
        imageUrl:
            p['image_front_url'] as String? ?? p['image_url'] as String?,
        category: category,
        quantity: p['quantity'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  // ── ean-search.org ────────────────────────────────────────────────────────

  Future<Product?> _fetchEanSearch(String barcode) async {
    try {
      final uri = Uri.parse(
        'https://api.ean-search.org/api'
        '?token=$eanSearchApiKey'
        '&op=barcode-lookup'
        '&ean=$barcode'
        '&format=json',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);

      // Response is a list: [{"ean":"...","name":"...","categoryId":"..."}]
      final list = json as List<dynamic>?;
      if (list == null || list.isEmpty) return null;
      final item = list.first as Map<String, dynamic>;
      final name = (item['name'] as String? ?? '').trim();
      if (name.isEmpty) return null;

      return Product(
        barcode: barcode,
        name: name,
        brand: _gs1BrandFromBarcode(barcode) ?? '',
        category: item['categoryName'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  // ── GS1 company prefix fallback ───────────────────────────────────────────

  /// Returns a partial Product with brand name derived from the GS1 company
  /// prefix embedded in the barcode. No API call — instant, always works for
  /// known companies.
  Product? _gs1FallbackProduct(String barcode) {
    final brand = _gs1BrandFromBarcode(barcode);
    if (brand == null) return null;
    return Product(
      barcode: barcode,
      name: '$brand Product',
      brand: brand,
      isPartialMatch: true,
    );
  }

  String? _gs1BrandFromBarcode(String barcode) {
    for (final entry in _gs1CompanyPrefixes.entries) {
      if (barcode.startsWith(entry.key)) return entry.value;
    }
    return null;
  }

  // ── GS1 company prefix table ──────────────────────────────────────────────
  // Format: barcode-prefix → company/brand name
  // Indian brands (890x prefix = GS1 India) + major global brands

  static const _gs1CompanyPrefixes = <String, String>{
    // ── Indian brands ────────────────────────────────────────────
    '8901030': 'Hindustan Unilever',
    '8901396': 'Procter & Gamble India',
    '8906001': 'Patanjali',
    '8906024': 'Marico',
    '8901764': 'Nestlé India',
    '8901058': 'ITC',
    '8901063': 'Dabur',
    '8901719': 'Emami',
    '8906009': 'Himalaya',
    '8906016': 'Wipro Consumer',
    '8901043': 'Parle',
    '8901491': 'Britannia',
    '8901042': 'Amul',
    '8901099': 'Mother Dairy',
    '8906022': 'Godrej Consumer',
    '8901262': 'Pepsi India',
    '8901012': 'Coca-Cola India',
    '8901571': 'Cadbury India',
    '8906038': 'Tata Consumer',
    '8901088': 'Heinz India',
    '8906127': 'Reckitt India',
    '8906005': 'Colgate India',
    '8901629': 'Johnson & Johnson India',
    // ── L'Oreal group ─────────────────────────────────────────────
    '3616303': 'L\'Oréal',
    '3600521': 'L\'Oréal Paris',
    '3600522': 'Garnier',
    '3600523': 'Maybelline',
    '3600524': 'L\'Oréal Professionnel',
    '3474630': 'L\'Oréal',
    // ── Global FMCG ────────────────────────────────────────────────
    '5449000': 'Coca-Cola',
    '5000159': 'Mars',
    '7622210': 'Mondelez',
    '4008400': 'Nivea (Beiersdorf)',
    '4005808': 'Nivea (Beiersdorf)',
    '5010663': 'Unilever',
    '8710908': 'Unilever',
    '5000282': 'Unilever',
    '3017620': 'Ferrero',
    '8076800': 'Barilla',
    '4000539': 'Schwarzkopf',
    '5900866': 'Henkel',
    '5413149': 'Colgate-Palmolive',
    '0037000': 'Procter & Gamble',
    '0030000': 'Kellogg\'s',
    '0016000': 'General Mills',
    '0070177': 'Unilever (US)',
    '0041000': 'Nestlé (US)',
    '0028000': 'Heinz',
    '0044000': 'Kraft',
    '0051000': 'Campbell\'s',
    '0071741': 'Dole',
    '0048001': 'PepsiCo',
    '0012000': 'Coca-Cola (US)',
    '0073490': 'Red Bull',
    '5010034': 'Reckitt',
    '5000325': 'GlaxoSmithKline',
    '9300605': 'Woolworths (AU)',
    '9310015': 'Arnott\'s (AU)',
  };
}
