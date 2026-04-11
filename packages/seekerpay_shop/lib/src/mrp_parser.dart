import 'mrp_data.dart';

/// Parses raw OCR text from a price / MRP sticker.
///
/// Supports any currency — detects the symbol or ISO code from the label text
/// and returns it alongside the raw amount so the caller can convert to USD.
///
/// Currency detection priority:
///   1. Explicit ISO code on label ("USD", "GBP", "EUR", "INR", …)
///   2. Currency symbol (₹ → INR, $ → USD, £ → GBP, € → EUR, ¥ → JPY, …)
///   3. "MRP" keyword with no other indicator → INR (legal requirement in India)
///
/// Handles formats seen on real stickers:
///   MRP ₹: 1699.00       ← Indian (₹ with colon)
///   MRP Rs. 349.00        ← Indian (Rs. format)
///   MRP: USD 12.99        ← explicit ISO code
///   Price: £ 9.99         ← British
///   Prix: 12,99 €         ← European (comma decimal)
///   Price $ 5.00          ← US
///   USP Rs. 2.33 Per/ml   ← per-unit price
///   NET QUANTITY: 90 UNITS OF TABLETS
class MrpParser {
  MrpParser._();

  static String _country = 'India';
  static void configure({String? country}) {
    if (country != null) _country = country;
  }

  static MrpData parse(String rawText) {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final priceInfo = _extractPriceInfo(rawText);
    var currency = priceInfo?.$2;
    if (currency == null) {
      if (_country == 'India' && rawText.toUpperCase().contains('MRP')) {
        currency = 'INR';
      } else if (_country != 'India') {
        currency = 'USD';
      }
    }

    return MrpData(
      productName: _extractProductName(lines, rawText),
      mrpAmount: priceInfo?.$1,
      currencyCode: currency,
      perUnitPrice: _extractPerUnitPrice(rawText),
      quantity: _extractQuantity(rawText),
      brand: _extractBrand(rawText),
      batchNo: _extractBatchNo(rawText),
      mfgDate: _extractMfgDate(rawText),
      impDate: _extractImpDate(rawText),
      expDate: _extractExpDate(rawText),
      rawText: rawText,
    );
  }

  // ── Currency detection ────────────────────────────────────────────────────

  /// Maps detected symbol/token → ISO 4217 code.
  static const _symbolMap = {
    '₹': 'INR',
    'rs.': 'INR',
    'rs': 'INR',
    're.': 'INR', // OCR misread of Rs.
    're': 'INR',  // OCR misread of Rs
    'inr': 'INR',
    '\$': 'USD',
    'usd': 'USD',
    '£': 'GBP',
    'gbp': 'GBP',
    '€': 'EUR',
    'eur': 'EUR',
    '¥': 'JPY',
    'jpy': 'JPY',
    'cny': 'CNY',
    'rmb': 'CNY',
    'aed': 'AED',
    'sgd': 'SGD',
    's\$': 'SGD',
    'myr': 'MYR',
    'rm': 'MYR',
    'thb': 'THB',
    '฿': 'THB',
    'aud': 'AUD',
    'a\$': 'AUD',
    'cad': 'CAD',
    'c\$': 'CAD',
    'chf': 'CHF',
    'krw': 'KRW',
    '₩': 'KRW',
    'brl': 'BRL',
    'r\$': 'BRL',
    'zar': 'ZAR',
    'r': 'ZAR', // South African Rand (ambiguous — only if "R " prefix)
    'nok': 'NOK',
    'sek': 'SEK',
    'dkk': 'DKK',
    'nzd': 'NZD',
    'hkd': 'HKD',
  };

  /// Detects ISO currency code from a symbol/token string found in the text.
  static String? _detectCurrency(String token) {
    final t = token.toLowerCase().trim();
    return _symbolMap[t];
  }

  // ── Price extraction ──────────────────────────────────────────────────────

  // Regex that matches per-unit qualifiers immediately after a number —
  // used to skip amounts like "2.33 per/ml" when extracting the MRP.
  static final _perUnitSuffix = RegExp(
    r'\s*(?:[Pp]er|/ml|/g\b|/kg|per\s*unit|p\.u\.)',
    caseSensitive: false,
  );

  /// Returns (amount, currencyCode) or null.
  static (double, String)? _extractPriceInfo(String text) {
    // Patterns in priority order — MRP-labelled patterns first so they win
    // over generic catch-alls.
    // Each entry: (regex, currencyGroupIndex or null, amountGroupIndex, fallbackCurrency)
    final candidates = <(String, int?, int, String?)>[
      // "MRP ₹ 349" / "MRP: Rs. 349.00" / "MRP Re. 349" (Re. = OCR misread of Rs.)
      (r'M\.?R\.?P\.?\s*[:\-]?\s*([₹]|R[se]\.?|INR)\s*[:\-]?\s*([\d,]+(?:[.,]\d{1,2})?)', 1, 2, null),
      // "MRP: USD 12.99" / "MRP: EUR 9.99"
      (r'M\.?R\.?P\.?\s*[:\-]?\s*([A-Z]{3})\s+([\d,]+(?:[.,]\d{1,2})?)', 1, 2, null),
      // "MRP: 1699" / "MRP 349" (no symbol → always INR by Indian law)
      (r'M\.?R\.?P\.?\s*[:\-]?\s*([\d,]+(?:[.,]\d{1,2})?)', null, 1, 'INR'),
      // Two-line OCR: "MRP ₹\n1699" — currency on MRP line, price on next line.
      // Handles two-column label layouts where the large price number is right-aligned
      // and OCR row grouping fails to merge it with the "MRP ₹" label.
      (r'M\.?R\.?P\.?\s*[:\-]?\s*([₹]|R[se]\.?|INR)[^\n]*\n\s*([\d,]+(?:[.,]\d{1,2})?)', 1, 2, null),
      // Same but no currency symbol on the MRP line
      (r'M\.?R\.?P\.?\s*[:\-]?\s*\n\s*([\d,]+(?:[.,]\d{1,2})?)', null, 1, 'INR'),
      // "Price: £ 9.99" / "Prix: 12.99 €"
      (r'[Pp]rice\s*[:\-]?\s*([£€\$¥₩฿]|[A-Z]{2,3}\.?)\s*([\d,]+(?:[.,]\d{1,2})?)', 1, 2, null),
      (r'[Pp]rice\s*[:\-]?\s*([\d,]+(?:[.,]\d{1,2})?)\s*([£€¥₩฿]|[A-Z]{2,3})', 2, 1, null),
      // Catch-all: "₹349" / "£9.99" / "Rs. 349" — but NOT per-unit prices
      // (per-unit prices are handled separately in _extractPerUnitPrice).
      (r'([₹£€¥₩฿\$]|Rs\.?)\s*([\d,]+(?:[.,]\d{1,2})?)', 1, 2, null),
      // "349 INR" / "12.99 USD" — ISO code after amount
      (r'([\d,]+(?:[.,]\d{1,2})?)\s*([A-Z]{3})\b', 2, 1, null),
    ];

    for (final (pattern, currencyIdx, amountIdx, fallbackCcy) in candidates) {
      for (final match in RegExp(pattern, caseSensitive: false).allMatches(text)) {
        // Parse amount — handle European comma decimal
        final rawAmount = match.group(amountIdx)!
            .replaceAll(RegExp(r'[^\d.,]'), '');
        final normAmount = _normaliseDecimal(rawAmount);
        final amount = double.tryParse(normAmount);
        if (amount == null || amount <= 0 || amount > 1000000) continue;

        // Skip per-unit prices: if the matched number is immediately followed
        // by "per", "/ml", "/g" etc. it is a unit price, not MRP.
        final afterMatch = text.substring(match.end);
        if (_perUnitSuffix.matchAsPrefix(afterMatch) != null) continue;

        // Determine currency
        String? ccy;
        if (currencyIdx != null) {
          ccy = _detectCurrency(match.group(currencyIdx)!);
        }
        ccy ??= fallbackCcy;
        if (ccy == null) continue;

        return (amount, ccy);
      }
    }
    return null;
  }

  /// Converts "12,99" → "12.99" (European decimal comma).
  /// Leaves "1,699.00" (thousands comma) unchanged.
  static String _normaliseDecimal(String raw) {
    // If there's a dot after a comma: "1,699.00" — keep as-is, remove commas.
    if (raw.contains('.') && raw.contains(',')) {
      return raw.replaceAll(',', '');
    }
    // If there's only a comma and it looks like a decimal separator
    // (fewer than 3 digits after): "12,99" → "12.99"
    final commaIdx = raw.lastIndexOf(',');
    if (commaIdx != -1 && !raw.contains('.')) {
      final afterComma = raw.substring(commaIdx + 1);
      if (afterComma.length <= 2) {
        return raw.substring(0, commaIdx) + '.' + afterComma;
      }
      // "1,699" — thousands separator, remove comma
      return raw.replaceAll(',', '');
    }
    return raw;
  }

  // ── Per-unit price extraction ─────────────────────────────────────────────

  static double? _extractPerUnitPrice(String text) {
    final patterns = [
      // "₹ per unit: 18.87"
      r'[₹\$£€]\s*per\s*unit\s*[:\-]?\s*([\d.]+)',
      // "USP Rs. 2.33 Per/ml" or "USP.Rs.2.33 Per /ml" (dot separator OCR)
      r'USP\.?\s*(?:R[se]\.?|₹|[A-Z]{3})\.?\s*([\d.]+)',
      // "Rs. X per unit" / "Re. X Per/ml"
      r'(?:R[se]\.?|[₹\$£€])\s*([\d.]+)\s*[Pp]er',
    ];
    for (final p in patterns) {
      final m = RegExp(p, caseSensitive: false).firstMatch(text);
      if (m != null) {
        final v = double.tryParse(m.group(1)!);
        if (v != null && v > 0) return v;
      }
    }
    return null;
  }

  // ── Product name extraction ───────────────────────────────────────────────

  /// Public entry point for name-only rescans from the UI.
  static String? extractNameOnly(List<String> lines, String text) =>
      _extractProductName(lines, text);

  static String? _extractProductName(List<String> lines, String text) {
    // 1. "Generic Name:" — allow OCR misreads like "Gereric Neme", "Generc Name" etc.
    //    Match any G-word (5-8 chars) followed by any N-word (2-5 chars) then the value.
    //    Covers: "Generic Name:", "Gereric Neme", "Generc Neme:", "Generic Neme" etc.
    final genericMatch = RegExp(
      r'[Gg][a-zA-Z]{4,7}\s+[Nn][a-zA-Z]{1,4}\s*[:\-]?\s*(.+)',
    ).firstMatch(text);
    if (genericMatch != null) {
      final name = genericMatch.group(1)?.trim() ?? '';
      if (name.isNotEmpty && name.length >= 3) return _cleanName(name);
    }

    // 2. "Product Name:" label
    final productMatch = RegExp(
      r'[Pp]roduct\s*[Nn]am[ea]\s*[:\-]?\s*(.+)',
    ).firstMatch(text);
    if (productMatch != null) {
      final name = productMatch.group(1)?.trim() ?? '';
      if (name.isNotEmpty) return _cleanName(name);
    }

    // 3. All-caps line — but must be a "clean" word (not garbled OCR noise).
    //    Reject lines that start with non-letter chars, have many short tokens,
    //    or look like address/metadata.
    for (final line in lines) {
      if (line.length < 4) continue;
      if (line != line.toUpperCase()) continue;
      if (line.contains(RegExp(r'\d'))) continue;
      if (_isAddress(line)) continue;
      if (_isMetadata(line)) continue;
      // Reject lines starting with punctuation (garbled OCR artifacts like ":STRUCCN")
      if (line.startsWith(RegExp(r'[^A-Z]'))) continue;
      // Reject lines that look like garbled text:
      // too many very-short words (< 3 chars) = likely OCR noise
      final words = line.split(RegExp(r'\s+'));
      final shortWords = words.where((w) => w.length < 3).length;
      if (words.length > 2 && shortWords > words.length ~/ 2) continue;

      return _cleanName(line);
    }

    return null;
  }

  // ── Quantity extraction ───────────────────────────────────────────────────

  static String? _extractQuantity(String text) {
    final patterns = [
      r'[Nn]et\s*[Qq]uantity\s*[:\-]?\s*([^\n]+)',
      r'[Nn]et\s*[Cc]ontent\s*[:\-]?\s*([^\n]+)',
      r'[Nn]et\s*[Ww]t\.?\s*[:\-]?\s*([\d.]+\s*(?:g|G|kg|KG|gm))',
      r'[Cc]ontents?\s*[:\-]?\s*([\d.]+\s*(?:ml|ML|g|G|kg|KG|L))',
      r'\b(\d+\s*(?:ml|ML|g|G|kg|KG|L|litre|liter|gm))\b',
    ];
    for (final pattern in patterns) {
      final match = RegExp(pattern, caseSensitive: false).firstMatch(text);
      if (match != null) {
        final v = match.group(1)?.trim() ?? '';
        if (v.isNotEmpty) return _cleanName(v);
      }
    }
    return null;
  }

  // ── Brand extraction ──────────────────────────────────────────────────────

  static String? _extractBrand(String text) {
    final patterns = [
      r'[Mm]anufactured\s*[Bb]y\s*[:\-]?\s*([^\n,]+)',
      r'[Ii]mported\s*(?:[Aa]nd\s*)?[Dd]istributed\s*[Bb]y\s*[:\-]?\s*([^\n,]+)',
      r'[Mm]arketed\s*[Bb]y\s*[:\-]?\s*([^\n,]+)',
      r'[Pp]acked\s*[Bb]y\s*[:\-]?\s*([^\n,]+)',
      r'[Bb]rand\s*[:\-]?\s*([^\n]+)',
    ];
    for (final pattern in patterns) {
      final match = RegExp(pattern, caseSensitive: false).firstMatch(text);
      if (match != null) {
        final brand = match.group(1)?.trim() ?? '';
        if (brand.isNotEmpty) return _cleanName(brand);
      }
    }
    return null;
  }

  // ── Batch number extraction ───────────────────────────────────────────────

  static String? _extractBatchNo(String text) {
    return _extractField(text, [
      r'[Bb]atch\s*[Nn]o\.?\s*[:\-]?\s*([A-Za-z0-9/\-]+)',
      r'[Ll]ot\s*[Nn]o\.?\s*[:\-]?\s*([A-Za-z0-9/\-]+)',
      r'MFG\s*[Nn]o\.?\s*[:\-]?\s*(?:Code\s*)?([A-Za-z0-9/\-]+)',
    ]);
  }

  // ── Date extractions ──────────────────────────────────────────────────────

  static String? _extractMfgDate(String text) {
    return _extractField(text, [
      // "Month & Year of Mfg Apr 2024" — also handles OCR misreads:
      // "Mtp", "Mtg", "Mfp" etc. (any 3-char word starting with M)
      r'[Mm]onth\s*&?\s*[Yy]ea[rn]?\s*of\s*[Mm]\w{0,3}\.?\s*[:\-]?\s*([A-Za-z]{3}\s*\d{4})',
      r'[Mm]fg\.?\s*[Dd]ate\s*[:\-]?\s*(\d{1,2}/\d{4})',
      r'MFG\.?\s*[:\-]?\s*([A-Za-z]{3}\s*\d{4})',
      r'[Dd]ate\s*of\s*[Mm]anufacture\s*[:\-]?\s*([A-Za-z]{3}\s*\d{4})',
      r'[Mm]fg[^:]*[:\-]\s*(\d{1,2}/\d{2,4})',
    ]);
  }

  static String? _extractImpDate(String text) {
    return _extractField(text, [
      // Allow OCR misreads: "imp N 2024" instead of "imp Nov 2024"
      // Capture 1–3 letters + year (e.g. "N 2024" → still useful)
      r'[Mm]onth\s*&?\s*[Yy]ea[rn]?\s*of\s*[Ii]mp\.?\s*[:\-]?\s*([A-Za-z]{1,3}\s*\d{4})',
      r'[Ii]mport\s*[Dd]ate\s*[:\-]?\s*([A-Za-z]{3}\s*\d{4})',
    ]);
  }

  static String? _extractExpDate(String text) {
    return _extractField(text, [
      r'[Bb]est\s*[Bb]efore\s*[:\-]?\s*([A-Za-z]{3}\s*\d{4})',
      r'[Ee]xpiry\s*[:\-]?\s*(\d{1,2}/\d{4})',
      r'[Ee]xp\.?\s*[:\-]?\s*(\d{1,2}/\d{4})',
      r'[Ee]xpiry\s*[Dd]ate\s*[:\-]?\s*([A-Za-z]{3}\s*\d{4})',
      r'[Uu]se\s*[Bb]y\s*[:\-]?\s*([A-Za-z]{3}\s*\d{4})',
      r'[Ee]xp[^:]*[:\-]\s*(\d{1,2}/\d{2,4})',
    ]);
  }

  // ── Generic field extraction ──────────────────────────────────────────────

  static String? _extractField(String text, List<String> patterns) {
    for (final pattern in patterns) {
      final match = RegExp(pattern, caseSensitive: false).firstMatch(text);
      if (match != null) {
        final v = match.group(1)?.trim() ?? '';
        if (v.isNotEmpty) return v;
      }
    }
    return null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _cleanName(String raw) {
    return raw
        .split('\n')
        .first
        .replaceAll(RegExp(r"""[^\w\s\-&'"()./₹]"""), '')
        .trim();
  }

  static bool _isAddress(String line) {
    return RegExp(
      r'\b(?:\d{6}|street|road|avenue|nagar|colony|dist\.?|pin)\b',
      caseSensitive: false,
    ).hasMatch(line);
  }

  static bool _isMetadata(String line) {
    return RegExp(
      r'\b(?:MRP|MFG|EXP|LOT|BATCH|FSSAI|LIC|GST|CIN|TEL|FAX|www\.|http)\b',
      caseSensitive: false,
    ).hasMatch(line);
  }
}
