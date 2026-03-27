import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:convert' show base64Encode, jsonEncode, jsonDecode;

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:solana_mobile_client/solana_mobile_client.dart';
import 'package:solana_web3/solana_web3.dart' as web3;

class MwaException implements Exception {
  final String message;
  MwaException(this.message);
  @override
  String toString() => 'MwaException: $message';
}

class MwaUserRejectedException extends MwaException {
  MwaUserRejectedException() : super('User rejected the request');
}

class MwaTimeoutException extends MwaException {
  MwaTimeoutException() : super('Wallet connection timed out');
}

class MwaClient {
  MwaClient._();
  static final MwaClient instance = MwaClient._();

  static const _channel = MethodChannel('seekerpay/wallet');

  AuthorizationResult? _auth;
  bool _busy = false;

  bool get isAuthorized => _auth != null;

  void reset() {
    _auth = null;
    _busy = false;
  }

  Future<void> _sleep(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<_ClientCtx> _openClient({int attempts = 10}) async {
    final scenario = await LocalAssociationScenario.create();
    scenario.startActivityForResult(null).ignore();
    await _sleep(300);

    var tries = 0;
    while (true) {
      tries++;
      try {
        final client = await scenario.start()
            .timeout(const Duration(seconds: 15));
        return _ClientCtx(client, scenario);
      } on TimeoutException {
        await scenario.close();
        throw MwaTimeoutException();
      } catch (e) {
        final msg = e.toString();
        final retryable =
            msg.contains('Unable to connect to websocket server') ||
                msg.contains('ConnectionFailedException') ||
                msg.contains('ECONNREFUSED');
        if (!retryable || tries >= attempts) {
          try {
            await scenario.close();
          } catch (_) {}
          rethrow;
        }
        await _sleep(600);
      }
    }
  }

  Future<String?> connectWalletAndGetAddress({
    String identityName = 'SeekerPay',
    String cluster = 'mainnet-beta',
  }) async {
    if (!Platform.isAndroid) return null;
    if (_busy) return null;
    _busy = true;

    _ClientCtx? ctx;
    try {
      ctx = await _openClient();
      final client = ctx.client;

      AuthorizationResult? nextAuth;
      final currentAuth = _auth;
      if (currentAuth != null) {
        nextAuth = await client.reauthorize(
          identityName: identityName,
          authToken: currentAuth.authToken,
        );
      }
      nextAuth ??= await client.authorize(
        identityName: identityName,
        cluster: cluster,
      );
      if (nextAuth == null) return null;

      _auth = nextAuth;
      final key = _extractPublicKey(nextAuth);
      if (key == null) return null;
      return web3.Pubkey.fromUint8List(key).toBase58();
    } catch (_) {
      rethrow;
    } finally {
      _busy = false;
      try {
        await ctx?.scenario.close();
      } catch (_) {}
    }
  }

  Future<Uint8List?> signTransaction({
    required Uint8List transactionBytes,
    String identityName = 'SeekerPay',
    String cluster = 'mainnet-beta',
  }) async {
    if (!Platform.isAndroid || _busy) return null;
    _busy = true;

    _ClientCtx? ctx;
    try {
      ctx = await _openClient();
      final client = ctx.client;

      AuthorizationResult? auth = _auth;
      if (auth != null) {
        auth = await client.reauthorize(
          identityName: identityName,
          authToken: auth.authToken,
        );
      }
      auth ??= await client.authorize(
        identityName: identityName,
        cluster: cluster,
      );
      if (auth == null) return null;
      _auth = auth;

      final signed =
          await client.signTransactions(transactions: [transactionBytes]);
      if (signed.signedPayloads.isEmpty) return null;

      return signed.signedPayloads.first;
    } catch (_) {
      rethrow;
    } finally {
      _busy = false;
      try {
        await ctx?.scenario.close();
      } catch (_) {}
    }
  }

  Uint8List? _extractPublicKey(AuthorizationResult? auth) => auth?.publicKey;
}

class _ClientCtx {
  _ClientCtx(this.client, this.scenario);
  final MobileWalletAdapterClient client;
  final LocalAssociationScenario scenario;
}
