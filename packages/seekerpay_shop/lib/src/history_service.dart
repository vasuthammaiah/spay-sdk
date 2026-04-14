import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'order_model.dart';
import 'product_model.dart';
import 'storage/arweave_order_service.dart';

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

  /// True while a background Arweave sync is in progress.
  final bool isSyncing;

  const HistoryState({
    this.orders = const [],
    this.scannedProducts = const [],
    this.isSyncing = false,
  });

  HistoryState copyWith({
    List<Order>? orders,
    List<Product>? scannedProducts,
    bool? isSyncing,
  }) {
    return HistoryState(
      orders: orders ?? this.orders,
      scannedProducts: scannedProducts ?? this.scannedProducts,
      isSyncing: isSyncing ?? this.isSyncing,
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

  // Arweave service is created lazily on the first call that has a wallet
  // address. Re-created if the wallet address changes (e.g. wallet switch).
  ArweaveOrderService? _arweave;
  String? _arweaveWalletAddress;

  bool _syncInProgress = false;

  @override
  HistoryState build() {
    _load();
    return const HistoryState();
  }

  Future<void> _load() async {
    final data = await _localService.loadHistory();
    state = HistoryState.fromJson(data);
  }

  // ---------------------------------------------------------------------------
  // Lazy Arweave initialisation (wallet-address-keyed)
  // ---------------------------------------------------------------------------

  /// Returns a ready [ArweaveOrderService] keyed to [walletAddress].
  ///
  /// Creates a new instance if none exists yet or if the wallet address changed.
  /// The encryption key is derived from [walletAddress], so it is identical on
  /// every device and after any reinstall with the same wallet.
  Future<ArweaveOrderService?> _getArweave(String walletAddress) async {
    if (_arweave != null && _arweaveWalletAddress == walletAddress) {
      return _arweave;
    }
    try {
      _arweave = await ArweaveOrderService.init(walletAddress: walletAddress);
      _arweaveWalletAddress = walletAddress;
      return _arweave;
    } catch (e) {
      if (kDebugMode) debugPrint('[HistoryNotifier] Arweave init failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Background sync — bidirectional push + pull
  // ---------------------------------------------------------------------------

  /// Bidirectional Arweave sync for [walletAddress].
  ///
  /// 1. **Upload pass** — every local order not yet on Arweave is uploaded and
  ///    marked synced. This catches up on any orders that were saved while
  ///    offline or before the wallet was connected.
  /// 2. **Download pass** — every Arweave order absent from local storage is
  ///    pulled down, merged into local state, and written to the JSON cache.
  ///    This restores order history after a reinstall or on a new device.
  ///
  /// After merge, [historyProvider] state updates automatically, so both
  /// RECENT SALES and the full order history tab reflect the latest data.
  ///
  /// Call this once per session when the wallet address is known. Safe to call
  /// multiple times — a guard prevents concurrent runs.
  Future<void> startBackgroundSync(String walletAddress) async {
    if (walletAddress.isEmpty || _syncInProgress) return;
    _syncInProgress = true;
    state = state.copyWith(isSyncing: true);

    try {
      final arweave = await _getArweave(walletAddress);
      if (arweave == null) return;

      final result = await arweave.sync(
        walletAddress: walletAddress,
        localOrders: List.unmodifiable(state.orders),
      );

      if (kDebugMode) {
        debugPrint(
          '[HistoryNotifier] sync done — '
          'uploaded=${result.uploaded} pulled=${result.pulled.length}',
        );
      }

      if (result.pulled.isNotEmpty) {
        final localIds = {for (final o in state.orders) o.id};
        final newOrders =
            result.pulled.where((o) => !localIds.contains(o.id)).toList();

        if (newOrders.isNotEmpty) {
          final merged = [...state.orders, ...newOrders]
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

          // Also archive product entries from pulled orders into local catalog.
          final nextProducts = List<Product>.from(state.scannedProducts);
          for (final order in newOrders) {
            for (final item in order.items) {
              final i = nextProducts
                  .indexWhere((p) => p.barcode == item.product.barcode);
              if (i >= 0) {
                nextProducts[i] = item.product;
              } else {
                nextProducts.add(item.product);
              }
            }
          }

          state = state.copyWith(orders: merged, scannedProducts: nextProducts);
          await _localService.saveHistory(state.toJson());
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[HistoryNotifier] sync error: $e');
    } finally {
      _syncInProgress = false;
      state = state.copyWith(isSyncing: false);
    }
  }

  // ---------------------------------------------------------------------------
  // Mutating operations
  // ---------------------------------------------------------------------------

  Future<void> deleteOrder(String orderId) async {
    final nextOrders = state.orders.where((o) => o.id != orderId).toList();
    state = state.copyWith(orders: nextOrders);
    await _localService.saveHistory(state.toJson());
  }

  Future<void> deleteProduct(String barcode) async {
    final nextProducts =
        state.scannedProducts.where((p) => p.barcode != barcode).toList();
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

  /// Saves [order] to local storage and queues an immediate Arweave backup.
  ///
  /// [walletAddress] must be the connected Solana wallet address.
  /// Omit (or pass empty) to skip the Arweave backup (local-only save).
  Future<void> saveOrder(Order order, {String? walletAddress}) async {
    // Prevent duplicate order IDs.
    final nextOrders = state.orders.where((o) => o.id != order.id).toList();
    nextOrders.add(order);

    // Archive unique products from the order into the local catalog.
    final nextProducts = List<Product>.from(state.scannedProducts);
    for (final item in order.items) {
      final i =
          nextProducts.indexWhere((p) => p.barcode == item.product.barcode);
      if (i >= 0) {
        nextProducts[i] = item.product;
      } else {
        nextProducts.add(item.product);
      }
    }

    state = state.copyWith(orders: nextOrders, scannedProducts: nextProducts);
    await _localService.saveHistory(state.toJson());

    // Arweave backup — fire and forget, never blocks the UI.
    if (walletAddress != null && walletAddress.isNotEmpty) {
      _backupToArweave(order, walletAddress);
    }
  }

  Future<void> clearHistory() async {
    state = const HistoryState();
    await _localService.saveHistory(state.toJson());
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _backupToArweave(Order order, String walletAddress) {
    _getArweave(walletAddress).then((arweave) {
      if (arweave == null) return;
      arweave.saveOrder(order, walletAddress).then((txId) {
        arweave.markSynced(order.id);
        if (kDebugMode) {
          debugPrint('[HistoryNotifier] order ${order.id} backed up → tx=$txId');
        }
      }).catchError((Object e) {
        if (kDebugMode) {
          debugPrint('[HistoryNotifier] Arweave backup failed for ${order.id}: $e');
        }
        // Non-fatal: retried on the next startBackgroundSync.
      });
    });
  }
}

final historyProvider =
    NotifierProvider<HistoryNotifier, HistoryState>(HistoryNotifier.new);
