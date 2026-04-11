import 'dart:async';
import 'dart:io';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'currency_converter.dart';
import 'local_llm_service.dart';
import 'mrp_ai_reader.dart';
import 'mrp_data.dart';
import 'mrp_parser.dart';
import 'product_model.dart';
import 'history_service.dart';

const _kPrimary = Color(0xFFFFEB3B);
const _kSurface = Color(0xFF111111);
const _kGreen = Color(0xFF00E676);
const _kMinOcrChars  = 5;
const _kMinOcrLines  = 1;

enum _Status { camera, processing, llm, result, error }
enum _ConversionState { idle, loading, done, failed }

class _ScanLineAnimation extends StatefulWidget {
  final double width;
  const _ScanLineAnimation({required this.width});
  @override State<_ScanLineAnimation> createState() => _ScanLineAnimationState();
}
class _ScanLineAnimationState extends State<_ScanLineAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  @override void initState() { super.initState(); _anim = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true); }
  @override void dispose() { _anim.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _anim, builder: (context, child) => Positioned(top: 194 * _anim.value, left: 3, child: Container(width: widget.width, height: 2, decoration: BoxDecoration(color: _kPrimary, boxShadow: [BoxShadow(color: _kPrimary.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)]))));
  }
}

class MrpScanSheet extends ConsumerStatefulWidget {
  final void Function(Product product, double usdPrice) onConfirm;
  const MrpScanSheet({super.key, required this.onConfirm});
  static Future<void> show(BuildContext context, {required void Function(Product product, double usdPrice) onConfirm}) {
    return showGeneralDialog(context: context, barrierDismissible: false, barrierColor: Colors.black, transitionDuration: const Duration(milliseconds: 200), transitionBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child), pageBuilder: (_, __, ___) => MrpScanSheet(onConfirm: onConfirm));
  }
  @override ConsumerState<MrpScanSheet> createState() => _MrpScanSheetState();
}

class _MrpScanSheetState extends ConsumerState<MrpScanSheet> with SingleTickerProviderStateMixin {
  CameraController? _controller; bool _cameraReady = false; Offset? _focusPoint; bool _focusVisible = false; bool _focusLocked = false; Timer? _focusTimer;
  _Status _status = _Status.camera; MrpData? _mrpData; String _rawOcrText = ''; String _llmRawOutput = ''; bool _usedLlm = false; String? _errorMessage; _ConversionState _convState = _ConversionState.idle; double? _rateToUsd;
  final _nameCtrl = TextEditingController(); final _barcodeCtrl = TextEditingController(); final _priceCtrl = TextEditingController(); final _mrpPriceCtrl = TextEditingController(); double? _confirmedUsd; bool _isConfirmed = false; String? _capturedPath;
  static const _kFName = 'name', _kFBarcode = 'barcode', _kFPrice = 'price', _kFExpiry = 'expiry';
  bool _showRescanPanel = false; final _rescanFields = <String>{}; bool _rescanningFields = false; bool _isRescanMode = false; final _rescanModeFields = <String>{}; String _rescanNameBackup = '', _rescanBarcodeBackup = '';

  @override void initState() { super.initState(); _initCamera(); }
  @override void dispose() { if (!_isConfirmed && _capturedPath != null) { try { File(_capturedPath!).deleteSync(); } catch (_) {} } _focusTimer?.cancel(); _controller?.dispose(); _nameCtrl.dispose(); _barcodeCtrl.dispose(); _priceCtrl.dispose(); _mrpPriceCtrl.dispose(); super.dispose(); }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request(); if (!mounted) return;
    if (status.isDenied || status.isPermanentlyDenied) { setState(() { _status = _Status.error; _errorMessage = status.isPermanentlyDenied ? 'Camera permission permanently denied.\nOpen Settings → App → Permissions and enable Camera.' : 'Camera permission denied. Please allow camera access and try again.'; }); return; }
    final cameras = await availableCameras(); if (cameras.isEmpty) { if (mounted) setState(() { _status = _Status.error; _errorMessage = 'No camera found'; }); return; }
    final ctrl = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    try { await ctrl.initialize(); try { await ctrl.setFocusMode(FocusMode.auto); } catch (_) {} try { await ctrl.setFlashMode(FlashMode.off); } catch (_) {} await ctrl.setExposureMode(ExposureMode.auto); if (mounted) setState(() { _controller = ctrl; _cameraReady = true; }); } catch (e) { if (mounted) setState(() { _status = _Status.error; _errorMessage = '$e'; }); }
  }

  Future<void> _onTapFocus(TapDownDetails details, BoxConstraints constraints) async {
    final ctrl = _controller; if (ctrl == null || !_cameraReady) return;
    final x = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0), y = (details.localPosition.dy / constraints.maxHeight).clamp(0.0, 1.0);
    setState(() { _focusPoint = details.localPosition; _focusVisible = true; _focusLocked = false; }); _focusTimer?.cancel();
    try { await ctrl.setFocusMode(FocusMode.auto); await ctrl.setFocusPoint(Offset(x, y)); await ctrl.setExposurePoint(Offset(x, y)); _focusTimer = Timer(const Duration(milliseconds: 1000), () { if (mounted) setState(() => _focusLocked = true); _focusTimer = Timer(const Duration(milliseconds: 1000), () { if (mounted) setState(() => _focusVisible = false); }); }); } catch (_) { _focusTimer = Timer(const Duration(milliseconds: 1200), () { if (mounted) setState(() => _focusVisible = false); }); }
  }

  Future<void> _capture() async {
    final ctrl = _controller; if (ctrl == null || !ctrl.value.isInitialized) return;
    setState(() => _status = _Status.processing);
    try {
      final photo = await ctrl.takePicture(); final originalPath = photo.path;
      final bytes = await File(originalPath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      
      final List<String> ocrPaths = [];
      
      if (image != null) {
        if (image.width > image.height) { image = img.copyRotate(image, angle: 90); }
        final w = image.width; final h = image.height;
        final cropW = (w * 0.75).toInt(); final cropH = (h * 0.15).toInt();
        final startX = (w - cropW) ~/ 2; final startY = (h - cropH) ~/ 2;
        final cropped = img.copyCrop(image, x: startX, y: startY, width: cropW, height: cropH);
        
        // Save Original Crop
        final p1 = originalPath.replaceFirst('.jpg', '_c1.jpg');
        await File(p1).writeAsBytes(img.encodeJpg(cropped));
        ocrPaths.add(p1);
        _capturedPath = p1;

        // Variant 2: Grayscale
        final grayscale = img.grayscale(img.Image.from(cropped));
        final p2 = originalPath.replaceFirst('.jpg', '_c2.jpg');
        await File(p2).writeAsBytes(img.encodeJpg(grayscale));
        ocrPaths.add(p2);

        // Variant 3: Threshold (B&W)
        final threshold = img.luminanceThreshold(img.Image.from(grayscale), threshold: 0.5);
        final p3 = originalPath.replaceFirst('.jpg', '_c3.jpg');
        await File(p3).writeAsBytes(img.encodeJpg(threshold));
        ocrPaths.add(p3);

        // Variant 4: Inverted
        final inverted = img.invert(img.Image.from(grayscale));
        final p4 = originalPath.replaceFirst('.jpg', '_c4.jpg');
        await File(p4).writeAsBytes(img.encodeJpg(inverted));
        ocrPaths.add(p4);
      } else { 
        _capturedPath = originalPath;
        ocrPaths.add(originalPath);
      }
      
      final path = _capturedPath!;
      String? detectedBarcode; final barcodeScanner = BarcodeScanner();
      try { final barcodes = await barcodeScanner.processImage(InputImage.fromFilePath(path)); if (barcodes.isNotEmpty) detectedBarcode = barcodes.first.rawValue; } catch (_) {} finally { barcodeScanner.close(); }

      // ── MULTI-PASS OCR ──
      final List<String> results = await Future.wait(ocrPaths.map((p) => _runMlKitOcr(p)));
      
      // Cleanup temp filter files (keep the main preview crop)
      for (int i = 1; i < ocrPaths.length; i++) { try { File(ocrPaths[i]).deleteSync(); } catch (_) {} }

      final combinedRaw = [
        if (results[0].isNotEmpty) "[Pass 1: Original]\n${results[0]}",
        if (results.length > 1 && results[1].isNotEmpty) "[Pass 2: Grayscale]\n${results[1]}",
        if (results.length > 2 && results[2].isNotEmpty) "[Pass 3: Threshold]\n${results[2]}",
        if (results.length > 3 && results[3].isNotEmpty) "[Pass 4: Inverted]\n${results[3]}",
      ].join("\n\n");

      if (!mounted) return;
      setState(() { _rawOcrText = combinedRaw; });
      dev.log('[Scanner] Multi-Pass OCR Result:\n$combinedRaw', name: 'seekerpay_shop');

      if (combinedRaw.trim().isEmpty) { if (mounted) setState(() { _status = _Status.result; }); return; }

      if (detectedBarcode != null) {
        final localProducts = ref.read(historyProvider).scannedProducts;
        final match = localProducts.cast<Product?>().firstWhere((p) => p?.barcode == detectedBarcode, orElse: () => null);
        if (match != null) {
          await Future.delayed(const Duration(milliseconds: 1200));
          _nameCtrl.text = match.name; _barcodeCtrl.text = match.barcode; _mrpPriceCtrl.text = match.lastPriceUsd?.toStringAsFixed(2) ?? '';
          setState(() { _mrpData = MrpData(productName: match.name, barcode: match.barcode, mrpAmount: match.lastPriceUsd, currencyCode: 'USD', expDate: match.expiryDate); _status = _Status.result; });
          if (_mrpData!.currencyCode != null) _fetchRate(_mrpData!); return;
        }
      }

      await Future.delayed(const Duration(milliseconds: 1200));

      if (MrpAiReader.isConfigured && MrpAiReader.isEnabledSync) {
        try {
          if (mounted) setState(() => _status = _Status.llm);
          final aiData = await MrpAiReader.readFromImage(path, focusFields: _isRescanMode ? _rescanModeFields.toList() : null).timeout(const Duration(seconds: 30));
          final data = aiData.copyWith(barcode: detectedBarcode);
          if (!mounted) return;
          if (_isRescanMode) { _applyRescanMerge(data); } else { _populateFields(data); }
          return;
        } catch (_) {}
      }

      MrpData data;
      if (combinedRaw.trim().length >= _kMinOcrChars && await LocalLlmService.isEnabled()) {
        if (mounted) setState(() => _status = _Status.llm);
        final (llmData, llmOutput) = await LocalLlmService.extractFromTextWithOutput(combinedRaw, focusFields: _isRescanMode ? _rescanModeFields.toList() : null).timeout(const Duration(seconds: 60), onTimeout: () => (null, 'timeout'));
        if (llmData != null) { data = llmData.copyWith(barcode: detectedBarcode); if (mounted) setState(() { _usedLlm = true; _llmRawOutput = llmOutput; }); }
        else { data = MrpParser.parse(results[0]).copyWith(barcode: detectedBarcode); if (mounted) setState(() { _usedLlm = false; _llmRawOutput = llmOutput; }); }
      } else {
        data = MrpParser.parse(results[0]).copyWith(barcode: detectedBarcode);
        if (mounted) setState(() { _usedLlm = false; _llmRawOutput = ''; });
      }
      if (!mounted) return;
      if (_isRescanMode) { _applyRescanMerge(data); } else { _populateFields(data); }
    } catch (e) { if (mounted) setState(() { _status = _Status.error; _errorMessage = '$e'; }); }
  }

  Future<String> _runMlKitOcr(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(path));
      final List<TextLine> allLines = []; for (final block in result.blocks) { allLines.addAll(block.lines); }
      if (allLines.isEmpty) return '';
      allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
      final List<List<TextLine>> rows = [];
      if (allLines.isNotEmpty) {
        rows.add([allLines.first]);
        for (int i = 1; i < allLines.length; i++) {
          final line = allLines[i]; final lastRow = rows.last; final lastLine = lastRow.first;
          final verticalGap = (line.boundingBox.top - lastLine.boundingBox.bottom).abs();
          if (verticalGap < lastLine.boundingBox.height * 0.5) { lastRow.add(line); } else { rows.add([line]); }
        }
      }
      final List<String> reconstructedLines = [];
      for (final row in rows) { row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left)); reconstructedLines.add(row.map((l) => l.text).join(' ')); }
      return reconstructedLines.join('\n');
    } catch (_) { return ''; }
    finally { recognizer.close(); }
  }

  void _populateFields(MrpData data) {
    _nameCtrl.text = data.productName ?? ''; _barcodeCtrl.text = data.barcode ?? ''; _mrpPriceCtrl.text = data.mrpAmount?.toStringAsFixed(2) ?? '';
    setState(() { _mrpData = data; _status = _Status.result; });
    if (data.currencyCode != null) _fetchRate(data);
  }

  Future<void> _fetchRate(MrpData data) async {
    if (data.currencyCode == 'USD') { setState(() { _rateToUsd = 1.0; _convState = _ConversionState.done; }); if (data.hasPrice) { _priceCtrl.text = data.mrpAmount!.toStringAsFixed(2); _confirmedUsd = data.mrpAmount; } return; }
    setState(() => _convState = _ConversionState.loading);
    try {
      final rate = await CurrencyConverter.rateToUsd(data.currencyCode!); if (!mounted) return;
      if (rate == null) throw Exception('Rate not found');
      setState(() { _rateToUsd = rate; _convState = _ConversionState.done; });
      if (data.hasPrice) { final usd = data.mrpAmount! / rate; _priceCtrl.text = usd.toStringAsFixed(2); setState(() => _confirmedUsd = usd); }
    } catch (e) { if (mounted) setState(() => _convState = _ConversionState.failed); }
  }

  void _confirm() {
    _isConfirmed = true; final name = _nameCtrl.text.trim(); final barcode = _barcodeCtrl.text.trim(); final price = double.tryParse(_priceCtrl.text) ?? 0.0;
    if (name.isEmpty || price <= 0) return;
    final product = Product(barcode: barcode.isNotEmpty ? barcode : 'scanned_${DateTime.now().millisecondsSinceEpoch}', name: name, brand: _mrpData?.brand ?? 'Scanned via AI', category: 'Scanned', imageUrl: _capturedPath != null ? 'file://$_capturedPath' : null, quantity: _mrpData?.quantity, expiryDate: _mrpData?.expDate, lastPriceUsd: price, savedAt: DateTime.now());
    widget.onConfirm(product, price); Navigator.of(context).pop();
  }

  void _reset() { if (_capturedPath != null) { try { File(_capturedPath!).deleteSync(); } catch (_) {} _capturedPath = null; } setState(() { _status = _Status.camera; _mrpData = null; _rawOcrText = ''; _llmRawOutput = ''; _usedLlm = false; _errorMessage = null; _nameCtrl.clear(); _barcodeCtrl.clear(); _priceCtrl.clear(); _mrpPriceCtrl.clear(); _confirmedUsd = null; _isConfirmed = false; _isRescanMode = false; _rescanFields.clear(); }); }
  void _rescanName() { setState(() { _isRescanMode = true; _rescanModeFields.clear(); _rescanModeFields.add(_kFName); _rescanNameBackup = _nameCtrl.text; _status = _Status.camera; }); }
  void _rescanBarcode() { setState(() { _isRescanMode = true; _rescanModeFields.clear(); _rescanModeFields.add(_kFBarcode); _rescanBarcodeBackup = _barcodeCtrl.text; _status = _Status.camera; }); }
  void _rescanSelectedFields() { setState(() { _isRescanMode = true; _rescanModeFields.clear(); _rescanModeFields.addAll(_rescanFields); _rescanNameBackup = _nameCtrl.text; _rescanBarcodeBackup = _barcodeCtrl.text; _status = _Status.camera; }); }

  void _applyRescanMerge(MrpData newData) {
    var merged = _mrpData ?? const MrpData();
    if (_rescanModeFields.contains(_kFName)) { merged = merged.copyWith(productName: newData.productName); _nameCtrl.text = newData.productName?.isNotEmpty == true ? newData.productName! : _rescanNameBackup; }
    if (_rescanModeFields.contains(_kFBarcode)) { merged = merged.copyWith(barcode: newData.barcode); _barcodeCtrl.text = newData.barcode?.isNotEmpty == true ? newData.barcode! : _rescanBarcodeBackup; }
    if (_rescanModeFields.contains(_kFPrice) && newData.hasPrice) { merged = merged.copyWith(mrpAmount: newData.mrpAmount, currencyCode: newData.currencyCode); }
    if (_rescanModeFields.contains(_kFExpiry) && newData.expDate != null) { merged = merged.copyWith(expDate: newData.expDate); }
    _mrpPriceCtrl.text = merged.mrpAmount?.toStringAsFixed(2) ?? ''; _priceCtrl.clear();
    setState(() { _mrpData = merged; _status = _Status.result; _isRescanMode = false; });
    if (merged.currencyCode != null) _fetchRate(merged);
  }

  @override Widget build(BuildContext context) { return Scaffold(backgroundColor: Colors.black, body: SafeArea(child: _status == _Status.error ? _errorScreen() : (_status == _Status.result ? _resultScreen() : _cameraScreen()))); }

  Widget _cameraScreen() {
    return Stack(children: [
      if (_controller != null && _controller!.value.isInitialized) Positioned.fill(child: AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: CameraPreview(_controller!))),
      if (_cameraReady) Positioned.fill(child: GestureDetector(onTapDown: (d) => _onTapFocus(d, const BoxConstraints.expand()))),
      if (_status == _Status.processing || _status == _Status.llm) Positioned.fill(child: Container(color: Colors.black87, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [ const CircularProgressIndicator(strokeWidth: 3, color: _kPrimary), const SizedBox(height: 24), Text(_status == _Status.llm ? 'AI PARSING LABEL...' : 'READING TEXT...', style: const TextStyle(color: _kPrimary, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2)) ])))),
      Center(child: Container(width: 300, height: 200, decoration: BoxDecoration(border: Border.all(color: _kPrimary.withValues(alpha: 0.8), width: 3), borderRadius: BorderRadius.circular(20)), child: Stack(children: [ const _ScanLineAnimation(width: 294), Positioned(top: 10, left: 10, child: Container(width: 20, height: 2, color: _kPrimary)), Positioned(top: 10, left: 10, child: Container(width: 2, height: 20, color: _kPrimary)), Positioned(top: 10, right: 10, child: Container(width: 20, height: 2, color: _kPrimary)), Positioned(top: 10, right: 10, child: Container(width: 2, height: 20, color: _kPrimary)), Positioned(bottom: 10, left: 10, child: Container(width: 20, height: 2, color: _kPrimary)), Positioned(bottom: 10, left: 10, child: Container(width: 2, height: 20, color: _kPrimary)), Positioned(bottom: 10, right: 10, child: Container(width: 20, height: 2, color: _kPrimary)), Positioned(bottom: 10, right: 10, child: Container(width: 2, height: 20, color: _kPrimary)) ]))),
      if (_focusVisible && _focusPoint != null) Positioned(left: _focusPoint!.dx - 28, top: _focusPoint!.dy - 28, child: _FocusIndicator(locked: _focusLocked)),
      Positioned(top: 0, left: 0, right: 0, child: _topBar()), Positioned(bottom: 0, left: 0, right: 0, child: _bottomBar()),
    ]);
  }

  Widget _topBar() { return Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])), child: Row(children: [ GestureDetector(onTap: () => Navigator.of(context).pop(), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.close_rounded, color: Colors.white, size: 20))), const SizedBox(width: 12), const Expanded(child: Text('SCAN PRODUCT LABEL', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2))) ])); }
  Widget _bottomBar() { return Container(padding: const EdgeInsets.fromLTRB(24, 20, 24, 36), decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])), child: Column(children: [ Text(_focusLocked ? 'Focus locked — press capture' : 'Tap the label to focus first', style: const TextStyle(color: Colors.white54, fontSize: 11)), const SizedBox(height: 20), Row(mainAxisAlignment: MainAxisAlignment.center, children: [ GestureDetector(onTap: () async { final ctrl = _controller; if (ctrl == null) return; final next = ctrl.value.flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off; await ctrl.setFlashMode(next); setState(() {}); }, child: Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, color: _controller?.value.flashMode == FlashMode.torch ? _kPrimary.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1)), child: Icon(_controller?.value.flashMode == FlashMode.torch ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded, color: _controller?.value.flashMode == FlashMode.torch ? _kPrimary : Colors.white, size: 20))), const SizedBox(width: 32), GestureDetector(onTap: _capture, child: Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)), child: Center(child: Container(width: 64, height: 64, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white))))), const SizedBox(width: 32), const SizedBox(width: 52) ]) ])); }

  Widget _resultScreen() {
    final mrp = _mrpData; final hasData = mrp != null && (mrp.hasName || mrp.hasPrice);
    return Column(children: [
      if (_capturedPath != null)
        Stack(children: [
          SizedBox(height: 180, width: double.infinity, child: Image.file(File(_capturedPath!), fit: BoxFit.cover)),
          Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87])))),
          Positioned(top: 12, left: 16, child: GestureDetector(onTap: _reset, child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle), child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20)))),
          Positioned(top: 12, right: 16, child: GestureDetector(onTap: () => Navigator.of(context).pop(), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle), child: const Icon(Icons.close_rounded, color: Colors.white, size: 20)))),
          Positioned(bottom: 0, left: 0, right: 0, child: Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(children: [
              const Text('LABEL SCAN', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
              const Spacer(),
              GestureDetector(onTap: _reset, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white24)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.camera_alt_rounded, color: Colors.white70, size: 14), SizedBox(width: 6), Text('RESCAN', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1))]))),
            ]))),
        ])
      else
        Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
          GestureDetector(onTap: _reset, child: const Icon(Icons.arrow_back_rounded, color: Colors.white70, size: 22)),
          const SizedBox(width: 14),
          const Expanded(child: Text('LABEL SCAN', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 2))),
          IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 22)),
        ])),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 32), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _statusBanner(hasData),
        const SizedBox(height: 20),
        Row(children: [ _label('PRODUCT NAME'), const Spacer(), if (_nameCtrl.text.trim().isEmpty) GestureDetector(onTap: _rescanName, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(border: Border.all(color: _kPrimary.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(4)), child: const Icon(Icons.document_scanner_rounded, color: _kPrimary, size: 11)))]),
        const SizedBox(height: 6),
        TextField(controller: _nameCtrl, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800), decoration: const InputDecoration(hintText: 'Not detected', hintStyle: TextStyle(color: Colors.white24, fontSize: 13), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _kPrimary, width: 1.5))), onChanged: (_) => setState(() {})),
        const SizedBox(height: 20),
        Row(children: [ _label('BARCODE'), const Spacer(), if (_barcodeCtrl.text.trim().isEmpty) GestureDetector(onTap: _rescanBarcode, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(border: Border.all(color: _kPrimary.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(4)), child: const Icon(Icons.qr_code_scanner_rounded, color: _kPrimary, size: 11)))]),
        const SizedBox(height: 6),
        TextField(controller: _barcodeCtrl, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'monospace'), decoration: const InputDecoration(hintText: 'Not detected', hintStyle: TextStyle(color: Colors.white24, fontSize: 12), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _kPrimary, width: 1.5))), onChanged: (_) => setState(() {})),
        const SizedBox(height: 20),
        if (mrp != null) _infoChips(mrp),
        if (mrp != null && (mrp.expDate != null)) const SizedBox(height: 20),
        if (mrp != null) ...[ _label('PRICE FROM LABEL'), const SizedBox(height: 8), _pricePanel(mrp), const SizedBox(height: 20) ],
        _label('YOUR PRICE (USD)'), const SizedBox(height: 6),
        TextField(controller: _priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), autofocus: !hasData, style: const TextStyle(color: _kPrimary, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1), decoration: const InputDecoration(hintText: '0.00', hintStyle: TextStyle(color: Colors.white24, fontSize: 32, fontWeight: FontWeight.w900), prefixText: '\$ ', prefixStyle: TextStyle(color: _kPrimary, fontSize: 32, fontWeight: FontWeight.w900), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white12)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _kPrimary, width: 1.5))), onChanged: (v) => setState(() => _confirmedUsd = double.tryParse(v))),
        if (_confirmedUsd != null && mrp?.currencyCode != null && _rateToUsd != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('≈ ${mrp!.currencySymbol}${(_confirmedUsd! * _rateToUsd!).toStringAsFixed(2)} ${mrp.currencyCode}', style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w700))),
        const SizedBox(height: 24),
        _rescanPanel(), const SizedBox(height: 24),
        _actionButtons(), const SizedBox(height: 20),
      ])))
    ]);
  }

  Widget _statusBanner(bool hasData) { return Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: hasData ? _kGreen.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.05), border: Border.all(color: hasData ? _kGreen.withValues(alpha: 0.35) : Colors.white24), borderRadius: BorderRadius.circular(6)), child: Row(children: [ Icon(hasData ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded, size: 15, color: hasData ? _kGreen : Colors.white38), const SizedBox(width: 10), Expanded(child: Text(hasData ? 'Label read — review and edit if needed.' : 'Could not read clearly. Tap on label to focus, then scan again.', style: TextStyle(color: hasData ? _kGreen : Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, height: 1.4))), GestureDetector(onTap: _reset, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: _kPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: _kPrimary.withValues(alpha: 0.3))), child: const Icon(Icons.refresh_rounded, color: _kPrimary, size: 16))) ])); }
  Widget _infoChips(MrpData mrp) { final chips = <_Chip>[]; if (mrp.expDate != null) chips.add(_Chip('EXPIRY', mrp.expDate!, const Color(0xFFFF7043))); if (chips.isEmpty) return const SizedBox.shrink(); return Wrap(spacing: 8, runSpacing: 8, children: chips.map((c) => _chipWidget(c)).toList()); }
  Widget _chipWidget(_Chip c) { return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: _kSurface, borderRadius: BorderRadius.circular(6), border: Border.all(color: (c.color ?? Colors.white).withValues(alpha: 0.12))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [ Text(c.label, style: TextStyle(color: c.color ?? Colors.white38, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.5)), const SizedBox(height: 2), Text(c.value, style: TextStyle(color: c.color ?? Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)) ])); }
  Widget _pricePanel(MrpData mrp) { return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: _kSurface, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withOpacity(0.07))), child: Row(children: [ Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ Text(mrp.currencyCode ?? 'PRICE', style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)), const SizedBox(height: 4), TextField(controller: _mrpPriceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900), decoration: InputDecoration(prefixText: mrp.currencySymbol, prefixStyle: const TextStyle(color: Colors.white38, fontSize: 24, fontWeight: FontWeight.w900), isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero), onChanged: (v) { final val = double.tryParse(v); if (val != null && _rateToUsd != null && _rateToUsd! > 0) { final usd = val / _rateToUsd!; _priceCtrl.text = usd.toStringAsFixed(2); setState(() => _confirmedUsd = usd); } }), ])), const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Icon(Icons.arrow_forward_rounded, color: Colors.white24, size: 18)), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ Row(children: [ const Text('USD', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)), const SizedBox(width: 6), if (_convState == _ConversionState.loading) const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white38)) else if (_convState == _ConversionState.done) const Icon(Icons.wifi_rounded, color: _kGreen, size: 9) ]), const SizedBox(height: 4), if (_convState == _ConversionState.loading) const Text('fetching...', style: TextStyle(color: Colors.white38, fontSize: 14)) else Text('\$${double.tryParse(_priceCtrl.text)?.toStringAsFixed(2) ?? "0.00"}', style: const TextStyle(color: _kPrimary, fontSize: 24, fontWeight: FontWeight.w900)) ])) ])); }

  Widget _rescanPanel() {
    final mrp = _mrpData;
    final fieldDefs = <_FieldDef>[
      _FieldDef(_kFName, 'Product Name', mrp?.hasName == true, Icons.label_outline_rounded),
      _FieldDef(_kFBarcode, 'Barcode', _barcodeCtrl.text.isNotEmpty, Icons.qr_code_scanner_rounded),
      _FieldDef(_kFPrice, 'Price', mrp?.hasPrice == true, Icons.payments_outlined),
      _FieldDef(_kFExpiry, 'Expiry Date', mrp?.expDate != null, Icons.event_outlined),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('RESCAN SPECIFIC FIELDS', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: fieldDefs.map((f) => InkWell(onTap: () => setState(() => _rescanFields.contains(f.key) ? _rescanFields.remove(f.key) : _rescanFields.add(f.key)),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: _rescanFields.contains(f.key) ? _kPrimary.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(6), border: Border.all(color: _rescanFields.contains(f.key) ? _kPrimary.withValues(alpha: 0.4) : Colors.white12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [ Icon(f.icon, size: 14, color: _rescanFields.contains(f.key) ? _kPrimary : (f.detected ? Colors.white54 : Colors.orange)), const SizedBox(width: 8), Text(f.label, style: TextStyle(color: _rescanFields.contains(f.key) ? _kPrimary : (f.detected ? Colors.white70 : Colors.orange), fontSize: 11, fontWeight: FontWeight.w600)) ])))).toList()),
      if (_rescanFields.isNotEmpty) ...[ const SizedBox(height: 12), ElevatedButton.icon(onPressed: _rescanningFields ? null : _rescanSelectedFields, style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))), icon: const Icon(Icons.camera_alt_rounded, size: 16), label: const Text('RESCAN SELECTED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900))) ]
    ]);
  }

  Widget _actionButtons() { return Row(children: [ Expanded(child: OutlinedButton.icon(onPressed: _reset, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('START OVER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)), style: OutlinedButton.styleFrom(foregroundColor: Colors.white54, side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))))), const SizedBox(width: 12), Expanded(flex: 2, child: ElevatedButton(onPressed: (_confirmedUsd != null && _confirmedUsd! > 0) ? _confirm : null, style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.black, disabledBackgroundColor: Colors.white12, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))), child: const Text('CONFIRM & ADD', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)))) ]); }
  Widget _errorScreen() { return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [ const Icon(Icons.error_outline_rounded, color: Colors.white24, size: 56), const SizedBox(height: 20), Text(_errorMessage ?? 'Something went wrong', style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.5), textAlign: TextAlign.center), const SizedBox(height: 28), ElevatedButton(onPressed: _reset, style: ElevatedButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))), child: const Text('TRY AGAIN', style: TextStyle(fontWeight: FontWeight.w900))) ]))); }
  Widget _label(String t) => Text(t, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2));
}
class _FieldDef { final String key, label; final bool detected; final IconData icon; const _FieldDef(this.key, this.label, this.detected, this.icon); }
class _FocusIndicator extends StatefulWidget { final bool locked; const _FocusIndicator({required this.locked}); @override State<_FocusIndicator> createState() => _FocusIndicatorState(); }
class _FocusIndicatorState extends State<_FocusIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _anim; late final Animation<double> _scale;
  @override void initState() { super.initState(); _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 300)); _scale = Tween(begin: 1.4, end: 1.0).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut)); _anim.forward(); }
  @override void didUpdateWidget(_FocusIndicator old) { super.didUpdateWidget(old); if (widget.locked && !old.locked) { _anim.forward(from: 0); } }
  @override void dispose() { _anim.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) { final color = widget.locked ? _kPrimary : _kPrimary.withValues(alpha: 0.6); return ScaleTransition(scale: _scale, child: SizedBox(width: 56, height: 56, child: Stack(children: [ Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: widget.locked ? 2.5 : 1.5))), Center(child: Container(width: widget.locked ? 6 : 4, height: widget.locked ? 6 : 4, decoration: BoxDecoration(shape: BoxShape.circle, color: color))), if (widget.locked) Positioned(bottom: -18, left: 0, right: 0, child: Text('LOCKED', textAlign: TextAlign.center, style: TextStyle(color: _kPrimary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1))) ]))); }
}
class _Chip { final String label, value; final Color? color; const _Chip(this.label, this.value, [this.color]); }
