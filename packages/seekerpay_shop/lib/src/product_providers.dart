import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'product_model.dart';
import 'product_lookup_service.dart';
import 'product_catalog_service.dart';

final productLookupServiceProvider = Provider<ProductLookupService>(
  (_) => ProductLookupService(),
);

final productCatalogServiceProvider = Provider<ProductCatalogService>(
  (_) => ProductCatalogService(),
);

/// Async lookup: checks local catalog first, then hits Open Food Facts API.
/// Returns null if not found anywhere.
final productLookupProvider =
    FutureProvider.family<Product?, String>((ref, barcode) async {
  final catalog = ref.read(productCatalogServiceProvider);
  final local = await catalog.get(barcode);
  if (local != null) return local;

  // Load API key and enabled status from SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final apiKey = prefs.getString('spay_barcode_lookup_key');
  final enabled = prefs.getBool('spay_barcode_lookup_enabled') ?? false;

  final lookup = ProductLookupService(
    barcodeLookupApiKey: apiKey,
    enabled: enabled,
  );
  
  return lookup.lookup(barcode);
});

/// All products saved in the local catalog, sorted by most recently added.
final productCatalogProvider =
    FutureProvider<List<Product>>((ref) async {
  final catalog = ref.read(productCatalogServiceProvider);
  return catalog.getAll();
});

/// Notifier for managing catalog state reactively.
class ProductCatalogNotifier extends AsyncNotifier<List<Product>> {
  @override
  Future<List<Product>> build() async {
    return ref.read(productCatalogServiceProvider).getAll();
  }

  Future<void> save(Product product) async {
    await ref.read(productCatalogServiceProvider).save(product);
    ref.invalidateSelf();
  }

  Future<void> delete(String barcode) async {
    await ref.read(productCatalogServiceProvider).delete(barcode);
    ref.invalidateSelf();
  }
}

final productCatalogNotifierProvider =
    AsyncNotifierProvider<ProductCatalogNotifier, List<Product>>(
  ProductCatalogNotifier.new,
);
