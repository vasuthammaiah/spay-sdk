import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TokenPrices {
  final double solUsd;
  final double skrUsd;

  TokenPrices({required this.solUsd, required this.skrUsd});
}

class PriceService {
  final http.Client _client = http.Client();
  static const String _skrMint = 'SKRbvo6Gf7GondiT3BbTfuRDPqLWei4j2Qy2NPGZhW3';

  Future<TokenPrices> fetchPrices() async {
    try {
      // 1. Fetch SOL price
      final solResponse = await _client.get(
        Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=solana&vs_currencies=usd'),
      );

      // 2. Fetch SKR price via Contract Address (Solana network)
      final skrResponse = await _client.get(
        Uri.parse('https://api.coingecko.com/api/v3/simple/token_price/solana?contract_addresses=$_skrMint&vs_currencies=usd'),
      );

      double solPrice = 150.0; // Default fallback
      double skrPrice = 0.02026; // Default fallback

      if (solResponse.statusCode == 200) {
        final data = jsonDecode(solResponse.body);
        solPrice = (data['solana']['usd'] as num).toDouble();
      }

      if (skrResponse.statusCode == 200) {
        final data = jsonDecode(skrResponse.body);
        if (data[_skrMint.toLowerCase()] != null) {
          skrPrice = (data[_skrMint.toLowerCase()]['usd'] as num).toDouble();
        } else if (data[_skrMint] != null) {
          skrPrice = (data[_skrMint]['usd'] as num).toDouble();
        }
      }

      return TokenPrices(solUsd: solPrice, skrUsd: skrPrice);
    } catch (e) {
      // Return last known good or conservative defaults if API is throttled
      return TokenPrices(solUsd: 150.0, skrUsd: 0.02026);
    }
  }
}

final priceServiceProvider = Provider((ref) => PriceService());

final pricesProvider = FutureProvider<TokenPrices>((ref) async {
  final service = ref.watch(priceServiceProvider);
  return service.fetchPrices();
});
