import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'rpc_client.dart';
import 'wallet_state.dart';
import 'skr_token.dart';
import 'transaction_record.dart';
import 'transaction_parser.dart';
import 'balance_providers.dart';

class ActivityState {
  final List<TransactionRecord> transactions;
  final bool isLoading;
  final String? error;
  final String filter;

  ActivityState({
    required this.transactions,
    this.isLoading = false,
    this.error,
    this.filter = 'all',
  });

  ActivityState copyWith({
    List<TransactionRecord>? transactions,
    bool? isLoading,
    String? error,
    String? filter,
  }) {
    return ActivityState(
      transactions: transactions ?? this.transactions,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      filter: filter ?? this.filter,
    );
  }
}

class ActivityService extends StateNotifier<ActivityState> {
  final RpcClient _rpc;
  final String _address;
  final Ref _ref;

  ActivityService(this._rpc, this._address, this._ref) 
    : super(ActivityState(transactions: []));

  void setFilter(String filter) {
    state = state.copyWith(filter: filter);
  }

  Future<void> load() async {
    if (_address.isEmpty) return;

    // Check if Helius is configured via ref
    final hasHelius = _ref.read(hasHeliusKeyProvider);
    if (!hasHelius) {
      state = state.copyWith(
        isLoading: false, 
        error: 'Helius API key not configured'
      );
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      // Fetch signatures and filter to a rolling 7 days to reduce RPC load.
      final signatures = await _rpc.getSignaturesForAddress(_address, limit: 200);
      
      // Also pull signatures from the user's SKR token accounts
      final skrTokenAccounts = await _rpc.getTokenAccountAddressesByOwner(_address, SKRToken.mintAddress);
      final List<TxSignature> tokenSignatures = [];
      for (final acct in skrTokenAccounts) {
        final sigs = await _rpc.getSignaturesForAddress(acct, limit: 100);
        tokenSignatures.addAll(sigs);
      }

      final Map<String, TxSignature> merged = {
        for (final s in signatures) s.signature: s,
        for (final s in tokenSignatures) s.signature: s,
      };
      final allSignatures = merged.values.toList();
      
      if (allSignatures.isEmpty) {
        state = state.copyWith(isLoading: false, transactions: []);
        return;
      }

      final List<TransactionRecord> allTxs = [];
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final recentSigs = allSignatures.where((s) {
        if (s.blockTime == null) return true; 
        final ts = DateTime.fromMillisecondsSinceEpoch(s.blockTime! * 1000);
        return ts.isAfter(sevenDaysAgo);
      }).toList();

      if (recentSigs.isEmpty) {
        state = state.copyWith(isLoading: false, transactions: []);
        return;
      }

      const batchSize = 10;
      
      for (int i = 0; i < recentSigs.length; i += batchSize) {
        final end = (i + batchSize < recentSigs.length) ? i + batchSize : recentSigs.length;
        final batch = recentSigs.sublist(i, end);
        final sigStrings = batch.map((s) => s.signature).toList();
        
        var results = await _rpc.getTransactions(sigStrings);
        final nonNullCount = results.where((r) => r != null).length;
        if (results.isEmpty || nonNullCount == 0) {
          results = [];
          for (final sig in sigStrings) {
            final single = await _rpc.getTransaction(sig);
            results.add(single);
            await Future.delayed(const Duration(milliseconds: 20));
          }
        }
        
        for (int j = 0; j < results.length; j++) {
          final data = results[j];
          if (data == null || data is! Map<String, dynamic>) {
            continue;
          }

          final records = TransactionParser.parseMany(
            txData: data,
            userAddress: _address,
            signature: batch[j].signature,
            fallbackTimestamp: batch[j].blockTime != null 
                ? DateTime.fromMillisecondsSinceEpoch(batch[j].blockTime! * 1000)
                : null,
          );
          
          for (final record in records) {
            if (record.timestamp.isAfter(sevenDaysAgo)) {
              allTxs.add(record);
            }
          }
        }
        
        await Future.delayed(const Duration(milliseconds: 10));
      }
      
      allTxs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      state = state.copyWith(isLoading: false, transactions: List.from(allTxs));
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final activityServiceProvider = StateNotifierProvider.autoDispose<ActivityService, ActivityState>((ref) {
  final rpc = ref.watch(rpcClientProvider);
  final wallet = ref.watch(walletStateProvider);
  return ActivityService(rpc, wallet.address ?? '', ref);
});
