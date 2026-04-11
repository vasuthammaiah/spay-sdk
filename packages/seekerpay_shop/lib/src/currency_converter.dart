import 'dart:convert';
import 'package:http/http.dart' as http;

/// Converts any ISO 4217 currency to USD using the free open.er-api.com API.
///
/// Rates are cached in-memory for the lifetime of the app session and refreshed
/// after [_cacheValidityMs] (10 minutes) to avoid hammering the API.
///
/// Usage:
///   final rateToUsd = await CurrencyConverter.rateToUsd('INR');
///   // rateToUsd = 83.5 → ₹83.5 = $1
///   final usd = inrAmount / rateToUsd;
class CurrencyConverter {
  CurrencyConverter._();

  // Base URL — USD rates for all currencies: rates["INR"] = 83.5 means $1=₹83.5
  static const _baseUrl =
      'https://open.er-api.com/v6/latest/USD';

  static const _cacheValidityMs = 10 * 60 * 1000; // 10 minutes

  // In-memory cache: currencyCode → unitsPerUsd
  static final Map<String, double> _cache = {};
  static int _lastFetchMs = 0;
  static bool _fetchInProgress = false;

  /// Returns how many units of [currencyCode] equal 1 USD.
  ///
  /// For example:
  ///   INR → ~83.5  (₹83.5 = $1)
  ///   GBP → ~0.79  (£0.79 = $1)
  ///   EUR → ~0.92  (€0.92 = $1)
  ///
  /// Returns null on network failure or unknown currency.
  static Future<double?> rateToUsd(String currencyCode) async {
    final code = currencyCode.toUpperCase();

    // USD itself — no conversion needed
    if (code == 'USD') return 1.0;

    // Check cache first
    final now = DateTime.now().millisecondsSinceEpoch;
    final cacheStale = (now - _lastFetchMs) > _cacheValidityMs;

    if (!cacheStale && _cache.containsKey(code)) {
      return _cache[code];
    }

    // Avoid parallel fetches
    if (_fetchInProgress) {
      // Wait for the in-progress fetch to complete and re-check cache
      await Future.delayed(const Duration(milliseconds: 300));
      return _cache[code];
    }

    _fetchInProgress = true;
    try {
      final uri = Uri.parse(_baseUrl);
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['result'] == 'success') {
          final rates = data['rates'] as Map<String, dynamic>;
          _cache.clear();
          for (final entry in rates.entries) {
            final rate = (entry.value as num).toDouble();
            if (rate > 0) _cache[entry.key] = rate;
          }
          _lastFetchMs = now;
        }
      }
    } catch (_) {
      // Network error — return cached value if available, else null
    } finally {
      _fetchInProgress = false;
    }

    return _cache[code];
  }

  /// Convenience: converts [amount] in [currencyCode] to USD.
  /// Returns null on failure.
  static Future<double?> toUsd(double amount, String currencyCode) async {
    final rate = await rateToUsd(currencyCode);
    if (rate == null || rate <= 0) return null;
    return amount / rate;
  }

  /// Clears the in-memory rate cache (useful for testing).
  static void clearCache() {
    _cache.clear();
    _lastFetchMs = 0;
  }
}
