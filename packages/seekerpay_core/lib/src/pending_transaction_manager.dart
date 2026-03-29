import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A signed transaction that has been stored locally for deferred on-chain submission.
class PendingTransaction {
  /// Base58 transaction signature derived from the signed payload.
  final String signature;

  /// Base64-encoded signed transaction bytes ready to submit to the RPC.
  final String signedTxBase64;

  /// Local time at which the transaction was signed and queued.
  final DateTime createdAt;

  /// Optional human-readable label for display purposes.
  final String? label;

  /// Base58 recipient address for single-transfer transactions, if known.
  final String? recipient;

  /// Transfer amount in SKR base units, if known.
  final BigInt? amount;

  /// Last submission error message, populated by [PendingTransactionManager.update].
  final String? error;

  PendingTransaction({
    required this.signature,
    required this.signedTxBase64,
    required this.createdAt,
    this.label,
    this.recipient,
    this.amount,
    this.error,
  });

  /// Serialises this transaction to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'signature': signature,
    'signedTxBase64': signedTxBase64,
    'createdAt': createdAt.toIso8601String(),
    'label': label,
    'recipient': recipient,
    'amount': amount?.toString(),
    'error': error,
  };

  /// Deserialises a [PendingTransaction] from a map produced by [toJson].
  factory PendingTransaction.fromJson(Map<String, dynamic> json) => PendingTransaction(
    signature: json['signature'],
    signedTxBase64: json['signedTxBase64'],
    createdAt: DateTime.parse(json['createdAt']),
    label: json['label'],
    recipient: json['recipient'],
    amount: json['amount'] != null ? BigInt.parse(json['amount']) : null,
    error: json['error'],
  );
}

/// Persists and manages a queue of signed-but-unsubmitted transactions using
/// [SharedPreferences].
class PendingTransactionManager {
  static const _key = 'seekerpay_pending_txs';

  /// Appends [tx] to the persisted queue.
  Future<void> add(PendingTransaction tx) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getAll();
    list.add(tx);
    await prefs.setStringList(_key, list.map((e) => jsonEncode(e.toJson())).toList());
  }

  /// Replaces the queued entry matching [tx.signature] with the new [tx] value.
  Future<void> update(PendingTransaction tx) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getAll();
    final index = list.indexWhere((e) => e.signature == tx.signature);
    if (index != -1) {
      list[index] = tx;
      await prefs.setStringList(_key, list.map((e) => jsonEncode(e.toJson())).toList());
    }
  }

  /// Returns all queued pending transactions.
  Future<List<PendingTransaction>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final strings = prefs.getStringList(_key) ?? [];
    return strings.map((e) => PendingTransaction.fromJson(jsonDecode(e))).toList();
  }

  /// Removes the queued transaction identified by [signature].
  Future<void> remove(String signature) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getAll();
    list.removeWhere((e) => e.signature == signature);
    await prefs.setStringList(_key, list.map((e) => jsonEncode(e.toJson())).toList());
  }

  /// Removes all queued pending transactions.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
