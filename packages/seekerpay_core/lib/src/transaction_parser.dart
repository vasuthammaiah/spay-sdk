import 'transaction_record.dart';
import 'skr_token.dart';

class TransactionParser {
  static BigInt? _parseUiAmount(Map<String, dynamic> ui) {
    final amountStr = ui['amount']?.toString();
    if (amountStr != null) {
      return BigInt.tryParse(amountStr);
    }
    final uiStr = ui['uiAmountString']?.toString();
    final decimals = ui['decimals'];
    if (uiStr == null || decimals is! int) return null;
    final parts = uiStr.replaceAll(',', '').split('.');
    final whole = parts[0];
    final frac = parts.length > 1 ? parts[1] : '';
    final padded = (frac + List.filled(decimals, '0').join()).substring(0, decimals);
    return BigInt.tryParse('$whole$padded');
  }

  static List<TransactionRecord> parseMany({
    required Map<String, dynamic> txData,
    required String userAddress,
    required String signature,
    DateTime? fallbackTimestamp,
  }) {
    try {
      final List<TransactionRecord> records = [];
      final meta = txData['meta'];
      final transaction = txData['transaction'];
      if (meta == null || transaction == null) return [];

      // Skip failed transactions for the main activity list to avoid confusion,
      // though they still cost fees.
      if (meta['err'] != null) return [];

      final blockTime = txData['blockTime'] as int?;
      final timestamp = blockTime != null
          ? DateTime.fromMillisecondsSinceEpoch(blockTime * 1000)
          : (fallbackTimestamp ?? DateTime.now());

      final message = transaction['message'];
      if (message == null) return [];

      final accountKeys = message['accountKeys'] as List?;
      if (accountKeys == null) return [];

      // Start with static account keys
      final List<String> addresses = accountKeys.map((k) {
        if (k is String) return k;
        if (k is Map) return (k['pubkey'] as String? ?? '');
        return '';
      }).toList();

      // Merge lookup-table resolved addresses (v0 transactions).
      // meta.loadedAddresses has {writable: [...], readonly: [...]} — appended
      // in that order after static keys, matching the accountIndex numbering.
      final loadedAddresses = meta['loadedAddresses'] as Map?;
      if (loadedAddresses != null) {
        final writable = loadedAddresses['writable'] as List? ?? [];
        final readonly = loadedAddresses['readonly'] as List? ?? [];
        for (final a in [...writable, ...readonly]) {
          addresses.add(a.toString());
        }
      }

      final targetAddr = userAddress.trim();

      // --- 1. Identify User Indices ---
      final userIndices = <int>{};
      for (int i = 0; i < addresses.length; i++) {
        if (addresses[i] == targetAddr) {
          userIndices.add(i);
        }
      }

      final preToken = meta['preTokenBalances'] as List? ?? [];
      final postToken = meta['postTokenBalances'] as List? ?? [];

      // Identify token accounts owned by the user or which the user is interacting with
      for (final b in [...preToken, ...postToken]) {
        final owner = b['owner']?.toString();
        final accountIndex = b['accountIndex'] as int?;
        if (accountIndex != null) {
          if (owner == targetAddr) {
            userIndices.add(accountIndex);
          }
        }
      }

      // --- 2. Check SKR Changes ---
      BigInt skrPre = BigInt.zero;
      BigInt skrPost = BigInt.zero;
      bool skrActivity = false;
      String? skrCounterparty;

      for (final b in preToken) {
        if (b['mint'] == SKRToken.mintAddress) {
          final accountIdx = b['accountIndex'] as int?;
          if (accountIdx != null && userIndices.contains(accountIdx)) {
            final ui = b['uiTokenAmount'] as Map<String, dynamic>?;
            final amount = ui != null ? _parseUiAmount(ui) : null;
            if (amount != null) {
              skrPre += amount;
            }
            skrActivity = true;
          }
        }
      }
      for (final b in postToken) {
        if (b['mint'] == SKRToken.mintAddress) {
          final accountIdx = b['accountIndex'] as int?;
          if (accountIdx != null) {
            final isUserAccount = userIndices.contains(accountIdx);
            final ui = b['uiTokenAmount'] as Map<String, dynamic>?;
            final amount = ui != null ? _parseUiAmount(ui) : null;

            if (isUserAccount) {
              if (amount != null) {
                skrPost += amount;
              }
              skrActivity = true;
            } else {
              // Potential counterparty — guard against lookup-table index overflow
              final owner = b['owner']?.toString();
              skrCounterparty = owner ??
                  (accountIdx < addresses.length ? addresses[accountIdx] : null);
            }
          }
        }
      }

      final skrDiff = skrPost - skrPre;
      
      // If no direct balance change detected, check instructions for SKR mentions
      if (!skrActivity || skrDiff == BigInt.zero) {
        final instructions = transaction['message']?['instructions'] as List? ?? [];
        final innerInstructions = meta['innerInstructions'] as List? ?? [];
        
        bool foundSkrInIx = false;
        for (final ix in instructions) {
          if (ix is Map && ix['parsed'] != null) {
            final info = ix['parsed']['info'];
            if (info != null && (info['mint'] == SKRToken.mintAddress || info['source'] == SKRToken.mintAddress)) {
              foundSkrInIx = true;
              break;
            }
          }
        }
        
        if (!foundSkrInIx) {
          for (final inner in innerInstructions) {
            final ixs = inner['instructions'] as List? ?? [];
            for (final ix in ixs) {
              if (ix is Map && ix['parsed'] != null) {
                final info = ix['parsed']['info'];
                if (info != null && (info['mint'] == SKRToken.mintAddress || info['source'] == SKRToken.mintAddress)) {
                  foundSkrInIx = true;
                  break;
                }
              }
            }
            if (foundSkrInIx) break;
          }
        }
        
        if (foundSkrInIx) {
          skrActivity = true;
          // Note: if diff is 0, it might be a complex tx where balance changes 
          // are hidden or net zero in simple terms, but we still want to show it.
        }
      }

      if (skrActivity && skrDiff != BigInt.zero) {
        records.add(TransactionRecord(
          signature: signature,
          timestamp: timestamp,
          amount: skrDiff.abs(),
          type: skrDiff > BigInt.zero ? TransactionType.receive : TransactionType.send,
          counterparty: skrCounterparty ?? 'SKR Transaction',
          symbol: 'SKR',
          decimals: SKRToken.decimals,
          mint: SKRToken.mintAddress,
        ));
      } else if (skrActivity) {
        // SKR mentioned but no net change (e.g. failed or complex)
        // We might want to show it as SKR still, but for now we fall through
      }

      // Only SKR token activity should be returned.

      return records;
    } catch (e) {
      return [];
    }
  }
}
