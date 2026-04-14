import 'dart:convert';
import 'package:http/http.dart' as http;
import 'product_model.dart';

/// A service for looking up product information by barcode.
/// 
/// It first attempts a premium lookup using the Barcode Lookup API if a key is provided.
/// If that fails or is unavailable, it falls back to the free Open Food Facts API.
class ProductLookupService {
  /// Optional API key for Barcode Lookup (premium).
  final String? barcodeLookupApiKey;
  
  /// Whether barcode lookup is enabled globally.
  final bool enabled;
  
  const ProductLookupService({this.barcodeLookupApiKey, this.enabled = true});

  /// Looks up a product by its barcode string.
  /// 
  /// Logic:
  /// 1. Cleans the input.
  /// 2. Checks if premium lookup (Barcode Lookup API) is enabled and has a key.
  /// 3. If premium fails or is skipped, attempts fallback to Open Food Facts.
  Future<Product?> lookup(String barcode) async {
    final cleaned = barcode.trim();
    if (cleaned.isEmpty) return null;

    final k = barcodeLookupApiKey?.trim() ?? '';
    
    print(' [Lookup] --- START LOOKUP: $barcode (Premium Enabled: $enabled) ---');
    
    // 1. Try Premium BarcodeLookup if key is available
    if (enabled && k.isNotEmpty) {
      final product = await _fetchBarcodeLookup(cleaned, k);
      if (product != null) return product;
    } else {
      print(' [Lookup] Premium BarcodeLookup skipped (Enabled: $enabled, Key present: ${k.isNotEmpty})');
    }

    // 2. Fallback to Open Food Facts (Free)
    // Open Food Facts is a community-driven database that provides free API access
    // for product information, including ingredients, brands, and categories.
    print(' [Lookup] Using fallback: Open Food Facts...');
    return await _fetchOpenFoodFacts(cleaned);
  }

  /// Internal method to fetch from Barcode Lookup API.
  Future<Product?> _fetchBarcodeLookup(String barcode, String key) async {
    try {
      final uri = Uri.parse('https://api.barcodelookup.com/v3/products?barcode=$barcode&formatted=y&key=$key');
      
      // THIS IS THE LINE THAT CALLS THE API
      print(' [Lookup] >>> EXECUTING NETWORK CALL: GET $uri');
      
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      print(' [Lookup] >>> HTTP STATUS: ${response.statusCode}');

      if (response.statusCode != 200) {
        print(' [Lookup] >>> API ERROR: ${response.body}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final list = json['products'] as List<dynamic>?;
      if (list == null || list.isEmpty) {
        print(' [Lookup] >>> API SUCCESS but product NOT FOUND in database.');
        return null;
      }

      final item = list.first as Map<String, dynamic>;
      final name = (item['title'] as String? ?? item['product_name'] as String? ?? '').trim();
      
      double? price;
      final stores = item['stores'] as List<dynamic>?;
      if (stores != null && stores.isNotEmpty) {
        final usd = stores.firstWhere((s) => s['currency'] == 'USD', orElse: () => null);
        final pick = usd ?? stores.first;
        price = double.tryParse(pick['price']?.toString() ?? '');
      }

      final imgList = item['images'] as List<dynamic>?;
      final imgUrl = imgList != null && imgList.isNotEmpty ? imgList.first.toString() : null;

      print(' [Lookup] >>> SUCCESS: Found $name');
      return Product(
        barcode: barcode,
        name: name,
        brand: item['brand'] as String? ?? item['manufacturer'] as String? ?? '',
        imageUrl: imgUrl,
        lastPriceUsd: price,
        category: item['category'] as String?,
      );
    } catch (e) { 
      print(' [Lookup] >>> EXCEPTION: $e'); 
      return null; 
    }
  }

  /// Internal method to fetch from Open Food Facts API as a fallback.
  Future<Product?> _fetchOpenFoodFacts(String barcode) async {
    try {
      final uri = Uri.parse('https://world.openfoodfacts.org/api/v2/product/$barcode.json');
      print(' [Lookup] >>> EXECUTING FALLBACK CALL: GET $uri');
      
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] != 1) {
        print(' [Lookup] >>> Open Food Facts: Product not found.');
        return null;
      }

      final item = json['product'] as Map<String, dynamic>;
      final name = (item['product_name'] as String? ?? '').trim();
      final brand = (item['brands'] as String? ?? '').trim();
      final imgUrl = item['image_url'] as String?;

      print(' [Lookup] >>> SUCCESS (Fallback): Found $name');
      return Product(
        barcode: barcode,
        name: name,
        brand: brand,
        imageUrl: imgUrl,
        category: item['categories'] as String?,
      );
    } catch (e) {
      print(' [Lookup] >>> FALLBACK EXCEPTION: $e');
      return null;
    }
  }
}
