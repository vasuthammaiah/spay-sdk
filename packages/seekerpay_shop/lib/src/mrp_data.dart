const _absent = Object();

class MrpData {
  final String? productName;
  final double? mrpAmount;
  final String? currencyCode;
  final double? perUnitPrice;
  final String? quantity;
  final String? brand;
  final String? batchNo;
  final String? mfgDate;
  final String? impDate;
  final String? expDate;
  final String? rawText;
  final String? barcode;
  final List<double> candidatePrices;

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
    this.candidatePrices = const [],
  });

  bool get hasPrice => mrpAmount != null && mrpAmount! > 0;
  bool get hasName => productName != null && productName!.isNotEmpty;

  String get currencySymbol {
    switch (currencyCode) {
      case 'INR': return '₹';
      case 'USD': return '\$';
      case 'GBP': return '£';
      case 'EUR': return '€';
      case 'JPY':
      case 'CNY': return '¥';
      default: return currencyCode ?? '?';
    }
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
    List<double>? candidatePrices,
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
      candidatePrices: candidatePrices ?? this.candidatePrices,
    );
  }
}
