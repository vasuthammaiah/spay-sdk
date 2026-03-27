import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'rpc_client.dart';
import 'skr_token.dart';
import 'wallet_state.dart';

const _defaultRpcUrl = 'https://api.mainnet-beta.solana.com';
const _heliusBaseUrl = 'https://mainnet.helius-rpc.com/?api-key=';

class RpcUrlNotifier extends StateNotifier<String> {
  String? _customRpcUrl;
  String? _heliusKey;

  RpcUrlNotifier() : super(_defaultRpcUrl) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _customRpcUrl = prefs.getString('rpc_url')?.trim();
    _heliusKey = prefs.getString('helius_api_key')?.trim();
    _recompute();
  }

  void _recompute() {
    if (_customRpcUrl != null && _customRpcUrl!.isNotEmpty) {
      state = _customRpcUrl!;
      return;
    }
    if (_heliusKey != null && _heliusKey!.isNotEmpty) {
      state = '$_heliusBaseUrl${_heliusKey!}';
      return;
    }
    state = _defaultRpcUrl;
  }

  Future<void> setRpcUrl(String url) async {
    final normalized = url.trim();
    final prefs = await SharedPreferences.getInstance();
    if (normalized.isEmpty) {
      await prefs.remove('rpc_url');
      _customRpcUrl = null;
      _recompute();
      return;
    }
    await prefs.setString('rpc_url', normalized);
    _customRpcUrl = normalized;
    _recompute();
  }

  Future<void> setHeliusKey(String key) async {
    final normalized = key.trim();
    final prefs = await SharedPreferences.getInstance();
    if (normalized.isEmpty) {
      await prefs.remove('helius_api_key');
      _heliusKey = null;
      _recompute();
      return;
    }
    await prefs.setString('helius_api_key', normalized);
    _heliusKey = normalized;
    _recompute();
  }
}

final rpcUrlProvider = StateNotifierProvider<RpcUrlNotifier, String>((ref) {
  return RpcUrlNotifier();
});

final hasHeliusKeyProvider = Provider<bool>((ref) {
  final rpcUrl = ref.watch(rpcUrlProvider);
  return rpcUrl.contains('helius-rpc.com');
});

final rpcClientProvider = Provider<RpcClient>((ref) {
  final rpcUrl = ref.watch(rpcUrlProvider);
  return RpcClient(rpcUrl: rpcUrl);
});

final skrBalanceProvider = FutureProvider<BigInt>((ref) async {
  final walletState = ref.watch(walletStateProvider);
  final rpcClient = ref.watch(rpcClientProvider);
  if (walletState.address == null) return BigInt.zero;
  
  return await rpcClient.getTokenAccountsByOwner(walletState.address!, SKRToken.mintAddress);
});

final solBalanceProvider = FutureProvider<BigInt>((ref) async {
  final walletState = ref.watch(walletStateProvider);
  final rpcClient = ref.watch(rpcClientProvider);
  if (walletState.address == null) return BigInt.zero;
  
  return await rpcClient.getBalance(walletState.address!);
});
