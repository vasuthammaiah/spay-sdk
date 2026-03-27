import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class RpcException implements Exception {
  final String message;
  RpcException(this.message);
  @override
  String toString() => 'RpcException: $message';
}

class SimulationResult {
  final bool hasError;
  final dynamic error;
  SimulationResult({required this.hasError, this.error});
}

class TxStatus {
  final String? status;
  final int? confirmations;
  TxStatus({this.status, this.confirmations});
}

class TxSignature {
  final String signature;
  final int? slot;
  final int? blockTime;
  TxSignature({required this.signature, this.slot, this.blockTime});
}

class RpcClient {
  final String rpcUrl;
  RpcClient({required this.rpcUrl});

  Future<dynamic> _post(String method, [List<dynamic>? params]) async {
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

  Future<BigInt> getBalance(String address) async {
    final result = await _post('getBalance', [address, {'commitment': 'confirmed'}]);
    return BigInt.from(result['value']);
  }

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

  Future<String> getLatestBlockhash() async {
    final result = await _post('getLatestBlockhash');
    return result['value']['blockhash'];
  }

  Future<SimulationResult> simulateTransaction(Uint8List txBytes) async {
    final result = await _post('simulateTransaction', [base64Encode(txBytes), {'encoding': 'base64'}]);
    return SimulationResult(hasError: result['value']['err'] != null, error: result['value']['err']);
  }

  Future<String> sendTransaction(Uint8List signedBytes) async {
    return await _post('sendTransaction', [base64Encode(signedBytes), {'encoding': 'base64'}]);
  }

  Future<List<TxStatus>> getSignatureStatuses(List<String> sigs) async {
    final result = await _post('getSignatureStatuses', [sigs]);
    return (result['value'] as List).map((v) => v == null ? TxStatus() : TxStatus(status: v['confirmationStatus'], confirmations: v['confirmations'])).toList();
  }

  Future<List<TxSignature>> getSignaturesForAddress(String address, {int limit = 20}) async {
    final result = await _post('getSignaturesForAddress', [address, {'limit': limit}]);
    return (result as List).map((item) => TxSignature(
      signature: item['signature'], 
      slot: item['slot'], 
      blockTime: item['blockTime'],
    )).toList();
  }

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

  Future<String?> snsResolveDomain(String domain) async {
    try {
      print('RpcClient: Resolving SNS domain: $domain');
      final result = await _post('sns_resolveDomain', [domain]);
      print('RpcClient: SNS Resolution result for $domain: $result');
      return result as String?;
    } catch (e) {
      print('RpcClient: SNS Resolution error for $domain: $e');
      return null;
    }
  }
}
