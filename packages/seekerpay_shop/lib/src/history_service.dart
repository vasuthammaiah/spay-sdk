import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'order_model.dart';
import 'product_model.dart';

class LocalHistoryService {
  static const _fileName = 'seekerpay_history.json';
  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }
  Future<Map<String, dynamic>> loadHistory() async {
    try {
      final f = await _file;
      if (!await f.exists()) return {};
      final s = await f.readAsString();
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) { return {}; }
  }
  Future<void> saveHistory(Map<String, dynamic> data) async {
    try {
      final f = await _file;
      await f.writeAsString(jsonEncode(data));
    } catch (_) {}
  }
}

class HistoryState {
  final List<Order> orders;
  final List<Product> scannedProducts;
  const HistoryState({this.orders = const [], this.scannedProducts = const []});
  
  HistoryState copyWith({List<Order>? orders, List<Product>? scannedProducts}) {
    return HistoryState(
      orders: orders ?? this.orders,
      scannedProducts: scannedProducts ?? this.scannedProducts,
    );
  }

  Map<String, dynamic> toJson() => {
    'orders': orders.map((o) => o.toJson()).toList(),
    'scannedProducts': scannedProducts.map((p) => p.toJson()).toList(),
  };
  factory HistoryState.fromJson(Map<String, dynamic> json) => HistoryState(
    orders: (json['orders'] as List? ?? []).map((o) => Order.fromJson(o)).toList(),
    scannedProducts: (json['scannedProducts'] as List? ?? []).map((p) => Product.fromJson(p)).toList(),
  );
}

class HistoryNotifier extends Notifier<HistoryState> {
  final _localService = LocalHistoryService();
  @override HistoryState build() { _load(); return const HistoryState(); }
  Future<void> _load() async {
    final data = await _localService.loadHistory();
    state = HistoryState.fromJson(data);
  }
  
  Future<void> deleteOrder(String orderId) async {
    final nextOrders = state.orders.where((o) => o.id != orderId).toList();
    state = state.copyWith(orders: nextOrders);
    await _localService.saveHistory(state.toJson());
  }

  Future<void> deleteProduct(String barcode) async {
    final nextProducts = state.scannedProducts.where((p) => p.barcode != barcode).toList();
    state = state.copyWith(scannedProducts: nextProducts);
    await _localService.saveHistory(state.toJson());
  }

  Future<void> updateProduct(Product product) async {
    final nextProducts = List<Product>.from(state.scannedProducts);
    final i = nextProducts.indexWhere((p) => p.barcode == product.barcode);
    if (i >= 0) { nextProducts[i] = product; } else { nextProducts.add(product); }
    state = state.copyWith(scannedProducts: nextProducts);
    await _localService.saveHistory(state.toJson());
  }

  Future<void> saveOrder(Order order) async {
    // Prevent duplicate order IDs in history
    final nextOrders = state.orders.where((o) => o.id != order.id).toList();
    nextOrders.add(order);
    
    // Also archive unique products from the order into inventory
    final nextProducts = List<Product>.from(state.scannedProducts);
    for (final item in order.items) {
      final i = nextProducts.indexWhere((p) => p.barcode == item.product.barcode);
      if (i >= 0) {
        nextProducts[i] = item.product; // Update existing
      } else {
        nextProducts.add(item.product); // Add new
      }
    }
    
    state = state.copyWith(orders: nextOrders, scannedProducts: nextProducts);
    await _localService.saveHistory(state.toJson());
  }
  Future<void> clearHistory() async {
    state = const HistoryState();
    await _localService.saveHistory(state.toJson());
  }
}

final historyProvider = NotifierProvider<HistoryNotifier, HistoryState>(HistoryNotifier.new);
