import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mwa_client.dart';

class WalletState {
  final String? address;
  final bool isConnecting;
  final String? error;

  WalletState({
    this.address,
    this.isConnecting = false,
    this.error,
  });

  WalletState copyWith({
    String? address,
    bool? isConnecting,
    String? error,
  }) {
    return WalletState(
      address: address ?? this.address,
      isConnecting: isConnecting ?? this.isConnecting,
      error: error,
    );
  }
}

class WalletStateNotifier extends StateNotifier<WalletState> {
  final MwaClient _mwaClient;

  WalletStateNotifier(this._mwaClient) : super(WalletState()) {
    _loadFromCache();
  }

  Future<void> _loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedAddress = prefs.getString('wallet_address');
    if (cachedAddress != null) {
      state = state.copyWith(address: cachedAddress);
    }
  }

  Future<void> connect() async {
    state = state.copyWith(isConnecting: true);
    try {
      final address = await _mwaClient.connectWalletAndGetAddress();
      if (address != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('wallet_address', address);
        state = state.copyWith(address: address, isConnecting: false);
      } else {
        state = state.copyWith(isConnecting: false, error: 'Connection failed');
      }
    } catch (e) {
      state = state.copyWith(isConnecting: false, error: e.toString());
    }
  }

  Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wallet_address');
    _mwaClient.reset();
    state = WalletState();
  }
}

final walletStateProvider = StateNotifierProvider<WalletStateNotifier, WalletState>((ref) {
  return WalletStateNotifier(MwaClient.instance);
});
