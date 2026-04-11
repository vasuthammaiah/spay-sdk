// Sentinel for copyWith — distinguishes "pass null" from "not provided".
const _absent = Object();

/// Parsed data extracted from an MRP / price sticker via OCR.
///
/// [currencyCode] is the ISO 4217 code detected from the label symbol,
/// e.g. "INR" for ₹/Rs., "USD" for $, "GBP" for £, "EUR" for €, etc.
/// Defaults to "INR" when a "MRP" label is present without a clear symbol
/// (MRP is an Indian legal requirement, so it is always INR).
class MrpData {
  final String? productName;

  /// Raw price amount in the currency shown on the label.
  final double? mrpAmount;

  /// ISO 4217 currency code detected from the label (e.g. "INR", "USD").
  final String? currencyCode;

  final double? perUnitPrice; // price per unit in the same currency
  final String? quantity;
  final String? brand;
  final String? batchNo;
  final String? mfgDate;
  final String? impDate; // Month & Year of Import
  final String? expDate;
  final String? rawText;
  final String? barcode;

  const MrpData({
    this.productName,
    this.mrpAmount,
    this.currencyCode,
    this.perUnitPrice,
    this.quantity,
    this.brand,
    this.batchNo,
    this.mfgDate,
    this.impDate,
    this.expDate,
    this.rawText,
    this.barcode,
  });

  bool get hasPrice => mrpAmount != null && mrpAmount! > 0;
  bool get hasName => productName != null && productName!.isNotEmpty;

  /// The currency symbol to show in the UI.
  String get currencySymbol {
    switch (currencyCode) {
      case 'INR':
        return '₹';
      case 'USD':
        return '\$';
      case 'GBP':
        return '£';
      case 'EUR':
        return '€';
      case 'JPY':
      case 'CNY':
        return '¥';
      case 'AED':
        return 'د.إ';
      case 'SGD':
        return 'S\$';
      case 'MYR':
        return 'RM';
      case 'THB':
        return '฿';
      case 'AUD':
        return 'A\$';
      case 'CAD':
        return 'C\$';
      default:
        return currencyCode ?? '?';
    }
  }

  /// Convert to USD using [rateToUsd] = how many units of this currency
  /// equal 1 USD (e.g. for INR: 83.5, for GBP: 0.79).
  double? toUsd(double rateToUsd) {
    if (!hasPrice || rateToUsd <= 0) return null;
    return mrpAmount! / rateToUsd;
  }

  MrpData copyWith({
    Object? productName = _absent,
    Object? mrpAmount = _absent,
    Object? currencyCode = _absent,
    Object? perUnitPrice = _absent,
    Object? quantity = _absent,
    Object? brand = _absent,
    Object? batchNo = _absent,
    Object? mfgDate = _absent,
    Object? impDate = _absent,
    Object? expDate = _absent,
    Object? rawText = _absent,
    Object? barcode = _absent,
  }) {
    return MrpData(
      productName:  productName  == _absent ? this.productName  : productName  as String?,
      mrpAmount:    mrpAmount    == _absent ? this.mrpAmount    : mrpAmount    as double?,
      currencyCode: currencyCode == _absent ? this.currencyCode : currencyCode as String?,
      perUnitPrice: perUnitPrice == _absent ? this.perUnitPrice : perUnitPrice as double?,
      quantity:     quantity     == _absent ? this.quantity     : quantity     as String?,
      brand:        brand        == _absent ? this.brand        : brand        as String?,
      batchNo:      batchNo      == _absent ? this.batchNo      : batchNo      as String?,
      mfgDate:      mfgDate      == _absent ? this.mfgDate      : mfgDate      as String?,
      impDate:      impDate      == _absent ? this.impDate      : impDate      as String?,
      expDate:      expDate      == _absent ? this.expDate      : expDate      as String?,
      rawText:      rawText      == _absent ? this.rawText      : rawText      as String?,
      barcode:      barcode      == _absent ? this.barcode      : barcode      as String?,
    );
  }

  @override
  String toString() =>
      'MrpData(name: $productName, price: $currencySymbol$mrpAmount, qty: $quantity, exp: $expDate)';
}
