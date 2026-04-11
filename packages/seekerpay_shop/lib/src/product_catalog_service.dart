import 'package:shared_preferences/shared_preferences.dart';
import 'product_model.dart';

/// Persists the shop owner's product catalog locally.
/// Key: barcode → JSON string of Product.
class ProductCatalogService {
  static const _prefix = 'spay_product_';

  Future<void> save(Product product) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefix${product.barcode}',
      product.copyWith(savedAt: DateTime.now()).toJsonString(),
    );
  }

  Future<Product?> get(String barcode) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$barcode');
    if (raw == null) return null;
    try {
      return Product.fromJsonString(raw);
    } catch (_) {
      return null;
    }
  }

  Future<List<Product>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final products = <Product>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        products.add(Product.fromJsonString(raw));
      } catch (_) {}
    }
    products.sort((a, b) =>
        (b.savedAt ?? DateTime(0)).compareTo(a.savedAt ?? DateTime(0)));
    return products;
  }

  Future<void> delete(String barcode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$barcode');
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
