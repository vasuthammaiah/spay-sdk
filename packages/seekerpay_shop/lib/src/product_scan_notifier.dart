import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'product_scan_state.dart';
import 'product_providers.dart';

class ProductScanNotifier extends Notifier<ProductScanState> {
  @override
  ProductScanState build() => const ProductScanState.scanning();

  Future<void> onBarcodeDetected(String barcode) async {
    if (state.status != ProductScanStatus.scanning) return;

    state = ProductScanState.loading(barcode);

    // 1. Check local catalog first
    final catalog = ref.read(productCatalogServiceProvider);
    final local = await catalog.get(barcode);
    if (local != null) {
      state = ProductScanState.found(local);
      return;
    }

    // 2. Hit Open Food Facts / Open Beauty Facts
    final lookup = ref.read(productLookupServiceProvider);
    final product = await lookup.lookup(barcode);

    if (product != null) {
      state = ProductScanState.found(product);
    } else {
      state = ProductScanState.notFound(barcode);
    }
  }

  void reset() => state = const ProductScanState.scanning();
}

final productScanProvider =
    NotifierProvider<ProductScanNotifier, ProductScanState>(
  ProductScanNotifier.new,
);
