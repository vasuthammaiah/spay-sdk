import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PendingTransaction {
  final String signature;
  final String signedTxBase64;
  final DateTime createdAt;
  final String? label;
  final String? recipient;
  final BigInt? amount;
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

  Map<String, dynamic> toJson() => {
    'signature': signature,
    'signedTxBase64': signedTxBase64,
    'createdAt': createdAt.toIso8601String(),
    'label': label,
    'recipient': recipient,
    'amount': amount?.toString(),
    'error': error,
  };

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

class PendingTransactionManager {
  static const _key = 'seekerpay_pending_txs';
  
  Future<void> add(PendingTransaction tx) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getAll();
    list.add(tx);
    await prefs.setStringList(_key, list.map((e) => jsonEncode(e.toJson())).toList());
  }

  Future<void> update(PendingTransaction tx) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getAll();
    final index = list.indexWhere((e) => e.signature == tx.signature);
    if (index != -1) {
      list[index] = tx;
      await prefs.setStringList(_key, list.map((e) => jsonEncode(e.toJson())).toList());
    }
  }

  Future<List<PendingTransaction>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final strings = prefs.getStringList(_key) ?? [];
    return strings.map((e) => PendingTransaction.fromJson(jsonDecode(e))).toList();
  }

  Future<void> remove(String signature) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await getAll();
    list.removeWhere((e) => e.signature == signature);
    await prefs.setStringList(_key, list.map((e) => jsonEncode(e.toJson())).toList());
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
