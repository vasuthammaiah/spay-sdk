import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'product_model.dart';
import 'product_scan_state.dart';
import 'product_scan_notifier.dart';
import 'product_providers.dart';

// Inline color constants — keeps SDK independent of seekerpay_ui
const _kPrimary = Color(0xFFFFEB3B);
const _kSurface = Color(0xFF111111);
const _kGreen = Color(0xFF00E676);

class ProductScanSheet extends ConsumerStatefulWidget {
  /// Called when the owner confirms a product with a price.
  /// [usdPrice] is what the owner typed — convert to SKR in the app layer.
  final void Function(Product product, double usdPrice) onConfirm;

  const ProductScanSheet({super.key, required this.onConfirm});

  /// Show the scan sheet as a full-height modal.
  static Future<void> show(
    BuildContext context, {
    required void Function(Product product, double usdPrice) onConfirm,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context),
        child: ProviderScope(
          overrides: [
            productScanProvider.overrideWith(ProductScanNotifier.new),
          ],
          child: ProductScanSheet(onConfirm: onConfirm),
        ),
      ),
    );
  }

  @override
  ConsumerState<ProductScanSheet> createState() => _ProductScanSheetState();
}

class _ProductScanSheetState extends ConsumerState<ProductScanSheet> {
  late final MobileScannerController _camera;
  final _priceController = TextEditingController();
  double? _enteredPrice;
  String _partialProductName = '';
  String _manualName = '';

  @override
  void initState() {
    super.initState();
    _camera = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _camera.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    _camera.stop();
    ref.read(productScanProvider.notifier).onBarcodeDetected(raw);
  }

  void _retry() {
    _priceController.clear();
    _enteredPrice = null;
    ref.read(productScanProvider.notifier).reset();
    _camera.start();
  }

  Future<void> _confirm(Product product) async {
    final price = _enteredPrice;
    if (price == null || price <= 0) return;

    final finalName = product.isPartialMatch && _partialProductName.isNotEmpty
        ? _partialProductName
        : product.name;
    final saved = product.copyWith(
      name: finalName,
      ownerPriceUsd: price,
      isPartialMatch: false,
    );
    await ref.read(productCatalogServiceProvider).save(saved);
    ref.invalidate(productCatalogNotifierProvider);

    if (mounted) {
      Navigator.of(context).pop();
      widget.onConfirm(saved, price);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanState = ref.watch(productScanProvider);
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.92,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text(
                  'SCAN PRODUCT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close_rounded, color: Colors.white54, size: 22),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Camera + overlay
          Expanded(
            child: Stack(
              children: [
                // Camera feed
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: scanState.status == ProductScanStatus.scanning ||
                          scanState.status == ProductScanStatus.loading
                      ? MobileScanner(
                          controller: _camera,
                          onDetect: _onDetect,
                        )
                      : Container(color: _kSurface),
                ),

                // Dark overlay with scan frame cutout
                CustomPaint(
                  painter: _ScanOverlayPainter(
                    active: scanState.status == ProductScanStatus.scanning,
                  ),
                  child: const SizedBox.expand(),
                ),

                // Status label over camera
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: _buildCameraLabel(scanState),
                ),
              ],
            ),
          ),

          // Bottom result panel
          _buildBottomPanel(scanState),
        ],
      ),
    );
  }

  Widget _buildCameraLabel(ProductScanState state) {
    String text;
    Color color;

    switch (state.status) {
      case ProductScanStatus.scanning:
        text = 'POINT AT BARCODE';
        color = Colors.white54;
      case ProductScanStatus.loading:
        text = state.barcode ?? '';
        color = _kPrimary;
      case ProductScanStatus.found:
        text = 'PRODUCT FOUND';
        color = _kGreen;
      case ProductScanStatus.notFound:
        text = 'NOT FOUND — ${state.barcode ?? ''}';
        color = Colors.white38;
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel(ProductScanState state) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: switch (state.status) {
        ProductScanStatus.scanning => _scanningHint(),
        ProductScanStatus.loading => _loadingPanel(state.barcode ?? ''),
        ProductScanStatus.found => _foundPanel(state.product!),
        ProductScanStatus.notFound => _notFoundPanel(state.barcode ?? ''),
      },
    );
  }

  Widget _scanningHint() {
    return Container(
      key: const ValueKey('scanning'),
      padding: const EdgeInsets.all(24),
      child: const Text(
        'Scan any product barcode — EAN, UPC, or QR code.',
        style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _loadingPanel(String barcode) {
    return Container(
      key: const ValueKey('loading'),
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _kPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'LOOKING UP $barcode',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _foundPanel(Product product) {
    return Container(
      key: const ValueKey('found'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: const BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Partial match banner
          if (product.isPartialMatch)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEB3B).withValues(alpha: 0.08),
                border: Border.all(color: const Color(0xFFFFEB3B).withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFFFFEB3B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Brand identified from barcode. Edit the product name below.',
                      style: const TextStyle(
                        color: Color(0xFFFFEB3B),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image
              if (product.imageUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    product.imageUrl!,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              if (product.imageUrl != null) const SizedBox(width: 14),

              // Product info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Editable name for partial matches
                    if (product.isPartialMatch)
                      TextField(
                        autofocus: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                        decoration: InputDecoration(
                          hintText: product.name.toUpperCase(),
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.w900),
                          isDense: true,
                          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: _kPrimary, width: 1.5)),
                        ),
                        onChanged: (v) => setState(() => _partialProductName = v),
                      )
                    else
                      Text(
                        product.name.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (product.brand.isNotEmpty) product.brand.toUpperCase(),
                        if (product.quantity != null) product.quantity!,
                      ].join(' · '),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (product.category != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          product.category!.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Price input
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'YOUR PRICE',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  autofocus: !product.hasOwnerPrice,
                  style: const TextStyle(
                    color: _kPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                  decoration: InputDecoration(
                    hintText: product.hasOwnerPrice
                        ? product.ownerPriceUsd!.toStringAsFixed(2)
                        : '0.00',
                    hintStyle: TextStyle(
                      color: product.hasOwnerPrice ? _kPrimary.withValues(alpha: 0.5) : Colors.white24,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                    suffixText: 'USD',
                    suffixStyle: const TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: _kPrimary, width: 1.5),
                    ),
                  ),
                  onChanged: (v) {
                    setState(() => _enteredPrice = double.tryParse(v));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              // Scan again
              Expanded(
                child: OutlinedButton(
                  onPressed: _retry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: const Text(
                    'SCAN AGAIN',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Confirm
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: (_enteredPrice != null && _enteredPrice! > 0) ||
                          product.hasOwnerPrice
                      ? () => _confirm(
                            product.copyWith(
                              ownerPriceUsd: _enteredPrice ?? product.ownerPriceUsd,
                            ),
                          )
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white12,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: const Text(
                    'SET & CONFIRM',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _notFoundPanel(String barcode) {
    return Container(
      key: const ValueKey('notFound'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      decoration: const BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'PRODUCT NOT FOUND',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            barcode,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontFamily: 'monospace',
              letterSpacing: 1,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Manual name + price entry for unknown products
          TextField(
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              hintText: 'Product name (optional)',
              hintStyle: TextStyle(color: Colors.white24, fontSize: 14),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _kPrimary, width: 1.5)),
            ),
            onChanged: (v) {
              // Used below when confirming manually
              setState(() => _manualName = v);
            },
          ),
          const SizedBox(height: 12),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'YOUR PRICE',
                style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: _kPrimary, fontSize: 24, fontWeight: FontWeight.w900),
                  decoration: const InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(color: Colors.white24, fontSize: 24, fontWeight: FontWeight.w900),
                    suffixText: 'USD',
                    suffixStyle: TextStyle(color: Colors.white38, fontSize: 13, fontWeight: FontWeight.w900),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _kPrimary, width: 1.5)),
                  ),
                  onChanged: (v) => setState(() => _enteredPrice = double.tryParse(v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _retry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: const Text('RETRY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _enteredPrice != null && _enteredPrice! > 0
                      ? () => _confirmManual(barcode)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white12,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  child: const Text('SAVE & CONFIRM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmManual(String barcode) async {
    final price = _enteredPrice;
    if (price == null || price <= 0) return;

    final product = Product(
      barcode: barcode,
      name: _manualName.isNotEmpty ? _manualName : barcode,
      brand: '',
      ownerPriceUsd: price,
    );
    await ref.read(productCatalogServiceProvider).save(product);
    ref.invalidate(productCatalogNotifierProvider);

    if (mounted) {
      Navigator.of(context).pop();
      widget.onConfirm(product, price);
    }
  }
}

// ─── Scan frame overlay ───────────────────────────────────────────────────────

class _ScanOverlayPainter extends CustomPainter {
  final bool active;

  _ScanOverlayPainter({required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    const frameSize = 220.0;
    const cornerLen = 22.0;
    const cornerRadius = 4.0;
    const strokeW = 3.0;

    final cx = size.width / 2;
    final cy = size.height / 2 - 20;

    final scanRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: frameSize,
      height: frameSize,
    );

    // Dark overlay with hole
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(cornerRadius))),
      ),
      overlayPaint,
    );

    // Corner brackets
    final bracketPaint = Paint()
      ..color = active ? const Color(0xFFFFEB3B) : Colors.white54
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round;

    final tl = scanRect.topLeft;
    final tr = scanRect.topRight;
    final bl = scanRect.bottomLeft;
    final br = scanRect.bottomRight;

    // Top-left
    canvas.drawLine(tl, tl + const Offset(cornerLen, 0), bracketPaint);
    canvas.drawLine(tl, tl + const Offset(0, cornerLen), bracketPaint);
    // Top-right
    canvas.drawLine(tr, tr + const Offset(-cornerLen, 0), bracketPaint);
    canvas.drawLine(tr, tr + const Offset(0, cornerLen), bracketPaint);
    // Bottom-left
    canvas.drawLine(bl, bl + const Offset(cornerLen, 0), bracketPaint);
    canvas.drawLine(bl, bl + const Offset(0, -cornerLen), bracketPaint);
    // Bottom-right
    canvas.drawLine(br, br + const Offset(-cornerLen, 0), bracketPaint);
    canvas.drawLine(br, br + const Offset(0, -cornerLen), bracketPaint);
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) => old.active != active;
}
