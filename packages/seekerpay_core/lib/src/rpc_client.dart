import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Exception thrown when a Solana JSON-RPC call returns an error or the
/// network request fails after all retries.
class RpcException implements Exception {
  /// Human-readable description of the RPC failure.
  final String message;
  RpcException(this.message);
  @override
  String toString() => 'RpcException: $message';
}

/// Result of a `simulateTransaction` RPC call.
class SimulationResult {
  /// `true` when the simulation returned a non-null error field.
  final bool hasError;

  /// The raw error value returned by the RPC node, or `null` on success.
  final dynamic error;
  SimulationResult({required this.hasError, this.error});
}

/// Confirmation status for a single transaction signature.
class TxStatus {
  /// Confirmation level reported by the RPC node (e.g. `"finalized"`), or
  /// `null` if the signature is not yet known.
  final String? status;

  /// Number of confirmations, or `null` when not provided by the node.
  final int? confirmations;
  TxStatus({this.status, this.confirmations});
}

/// A transaction signature entry returned by `getSignaturesForAddress`.
class TxSignature {
  /// Base58-encoded transaction signature.
  final String signature;

  /// Slot in which the transaction was confirmed, or `null` if unavailable.
  final int? slot;

  /// Unix timestamp (seconds) of the block, or `null` if unavailable.
  final int? blockTime;
  TxSignature({required this.signature, this.slot, this.blockTime});
}

/// Low-level Solana JSON-RPC client.
///
/// Wraps common RPC methods with automatic retries (up to 3 attempts) and
/// exponential back-off on HTTP 429 or transient network failures.
class RpcClient {
  /// The RPC endpoint URL used for all requests.
  final String rpcUrl;
  RpcClient({required this.rpcUrl});

  Future<dynamic> _post(String method, [dynamic params]) async {
    final response = await _postBatch([
      {
        'jsonrpc': '2.0',
        'id': 1,
        'method': method,
        if (params != null) 'params': params,
      }
    ]);
    final data = response[0];
    if (data['error'] != null) throw RpcException(data['error']['message']);
    return data['result'];
  }

  Future<List<dynamic>> _postBatch(List<Map<String, dynamic>> requests) async {
    int retries = 3;
    while (retries > 0) {
      try {
        final response = await http.post(
          Uri.parse(rpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requests.length == 1 ? requests[0] : requests),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 429) {
          retries--;
          if (retries > 0) {
            await Future.delayed(Duration(milliseconds: 500 * (3 - retries)));
            continue;
          }
        }

        if (response.statusCode != 200) {
          throw RpcException('HTTP Error: ${response.statusCode}');
        }

        final dynamic data = jsonDecode(response.body);
        if (data is Map) {
          return [data];
        } else if (data is List) {
          return data;
        } else {
          throw RpcException('Invalid RPC response format');
        }
      } catch (e) {
        if (retries > 1 && (e is http.ClientException || e.toString().contains('SocketException') || e.toString().contains('TimeoutException'))) {
          retries--;
          await Future.delayed(Duration(milliseconds: 500 * (3 - retries)));
          continue;
        }
        if (e is RpcException) rethrow;
        throw RpcException('Network error: ${e.toString()}');
      }
    }
    throw RpcException('RPC call failed after retries');
  }

  /// Returns the SOL balance of [address] in lamports (confirmed commitment).
  Future<BigInt> getBalance(String address) async {
    final result = await _post('getBalance', [address, {'commitment': 'confirmed'}]);
    return BigInt.from(result['value']);
  }

  /// Returns the token balance (in base units) for the first SPL token account
  /// owned by [address] for the given [mint], or [BigInt.zero] if none exist.
  Future<BigInt> getTokenAccountsByOwner(String address, String mint) async {
    final result = await _post('getTokenAccountsByOwner', [
      address,
      {'mint': mint},
      {'encoding': 'jsonParsed', 'commitment': 'confirmed'}
    ]);
    final accounts = result['value'] as List;
    if (accounts.isEmpty) return BigInt.zero;
    return BigInt.parse(accounts[0]['account']['data']['parsed']['info']['tokenAmount']['amount']);
  }

  /// Returns the public keys of all SPL token accounts owned by [address]
  /// for the given [mint].
  Future<List<String>> getTokenAccountAddressesByOwner(String address, String mint) async {
    final result = await _post('getTokenAccountsByOwner', [
      address,
      {'mint': mint},
      {'encoding': 'jsonParsed'}
    ]);
    final accounts = result['value'] as List;
    if (accounts.isEmpty) return [];
    return accounts.map((a) => a['pubkey'] as String).toList();
  }

  /// Fetches the latest blockhash string from the cluster.
  Future<String> getLatestBlockhash() async {
    final result = await _post('getLatestBlockhash');
    return result['value']['blockhash'];
  }

  /// Simulates [txBytes] (base64-encoded) and returns the simulation outcome.
  Future<SimulationResult> simulateTransaction(Uint8List txBytes) async {
    final result = await _post('simulateTransaction', [base64Encode(txBytes), {'encoding': 'base64'}]);
    return SimulationResult(hasError: result['value']['err'] != null, error: result['value']['err']);
  }

  /// Submits a signed, base64-encoded transaction and returns its signature.
  Future<String> sendTransaction(Uint8List signedBytes) async {
    return await _post('sendTransaction', [base64Encode(signedBytes), {'encoding': 'base64'}]);
  }

  /// Returns confirmation statuses for each signature in [sigs].
  Future<List<TxStatus>> getSignatureStatuses(List<String> sigs) async {
    final result = await _post('getSignatureStatuses', [sigs]);
    return (result['value'] as List).map((v) => v == null ? TxStatus() : TxStatus(status: v['confirmationStatus'], confirmations: v['confirmations'])).toList();
  }

  /// Returns the most recent transaction signatures involving [address],
  /// up to [limit] entries (default 20).
  Future<List<TxSignature>> getSignaturesForAddress(String address, {int limit = 20}) async {
    final result = await _post('getSignaturesForAddress', [address, {'limit': limit}]);
    return (result as List).map((item) => TxSignature(
      signature: item['signature'], 
      slot: item['slot'], 
      blockTime: item['blockTime'],
    )).toList();
  }

  /// Fetches the full transaction detail for [signature].
  ///
  /// Tries `jsonParsed` with `maxSupportedTransactionVersion: 1` first,
  /// then falls back to `jsonParsed` without the version hint, and finally
  /// to plain `json` encoding. Returns `null` if all attempts fail.
  Future<Map<String, dynamic>?> getTransaction(String signature) async {
    try {
      final result = await _post('getTransaction', [
        signature,
        {
          'encoding': 'jsonParsed',
          'commitment': 'confirmed',
          'maxSupportedTransactionVersion': 1,
        }
      ]);
      if (result != null) return result as Map<String, dynamic>?;
    } catch (_) {
      // fall through to retries
    }
    try {
      final result = await _post('getTransaction', [
        signature,
        {
          'encoding': 'jsonParsed',
          'commitment': 'confirmed',
        }
      ]);
      if (result != null) return result as Map<String, dynamic>?;
    } catch (_) {
      // fall through to retries
    }
    try {
      final result = await _post('getTransaction', [
        signature,
        {
          'encoding': 'json',
          'commitment': 'confirmed',
        }
      ]);
      return result as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Fetches transaction details for multiple [signatures] in a single batch
  /// RPC request. Returns an empty list on failure.
  Future<List<dynamic>> getTransactions(List<String> signatures) async {
    if (signatures.isEmpty) return [];
    try {
      final requests = signatures.asMap().entries.map((e) => {
        'jsonrpc': '2.0',
        'id': e.key + 1,
        'method': 'getTransaction',
        'params': [
          e.value,
          {
            'encoding': 'jsonParsed',
            'commitment': 'confirmed',
            'maxSupportedTransactionVersion': 1,
          }
        ]
      }).toList();

      final responses = await _postBatch(requests);
      return responses.map((r) => r['result']).toList();
    } catch (_) {
      return [];
    }
  }

  /// Helius DAS: returns all digital assets (including Token-2022 NFTs/tokens)
  /// owned by [address]. Params sent as a JSON object (DAS API convention).
  ///
  /// Set [showFungible] to `true` to include fungible Token-2022 assets such
  /// as the Seeker Genesis Token and Chapter 2 Preorder Token.
  Future<List<dynamic>> getAssetsByOwner(
    String address, {
    int limit = 1000,
    bool showFungible = false,
  }) async {
    final result = await _post('getAssetsByOwner', {
      'ownerAddress': address,
      'displayOptions': {
        'showFungible': showFungible,
        'showNativeBalance': false,
      },
      'limit': limit,
    });
    return (result?['items'] as List?) ?? [];
  }

  /// Returns the parsed account info for [address], or `null` if the account
  /// does not exist or the request fails.
  Future<Map<String, dynamic>?> getAccountInfo(String address) async {
    try {
      final result = await _post('getAccountInfo', [
        address,
        {'encoding': 'jsonParsed'}
      ]);
      return result['value'];
    } catch (_) {
      return null;
    }
  }

  /// Returns the raw account data bytes for [address], or null if the account
  /// does not exist. Used for on-chain SNS record parsing.
  Future<Uint8List?> getAccountData(String address) async {
    try {
      final result = await _post('getAccountInfo', [
        address,
        {'encoding': 'base64'},
      ]);
      final value = result['value'];
      if (value == null) return null;
      final data = value['data'];
      if (data is List && data.length == 2 && data[1] == 'base64') {
        return base64Decode(data[0] as String);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
