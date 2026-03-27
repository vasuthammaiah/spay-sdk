import 'dart:async';
import 'rpc_client.dart';

class ConfirmationTimeoutException implements Exception {
  final String message;
  ConfirmationTimeoutException(this.message);
}

class ConfirmationPoller {
  final RpcClient _rpcClient;
  ConfirmationPoller(this._rpcClient);

  Future<void> waitForConfirmation(String signature) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime) < const Duration(seconds: 60)) {
      try {
        final statuses = await _rpcClient.getSignatureStatuses([signature]);
        if (statuses.isNotEmpty && (statuses.first.status == 'finalized' || statuses.first.status == 'confirmed')) return;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 2));
    }
    throw ConfirmationTimeoutException('Transaction not confirmed within 60 seconds');
  }
}
