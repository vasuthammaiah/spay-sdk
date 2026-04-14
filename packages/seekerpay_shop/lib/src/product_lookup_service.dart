import 'dart:convert';
import 'package:http/http.dart' as http;
import 'product_model.dart';

class ProductLookupService {
  final String? barcodeLookupApiKey;
  final bool enabled;
  
  const ProductLookupService({this.barcodeLookupApiKey, this.enabled = true});

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
    print(' [Lookup] Using fallback: Open Food Facts...');
    return await _fetchOpenFoodFacts(cleaned);
  }

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
