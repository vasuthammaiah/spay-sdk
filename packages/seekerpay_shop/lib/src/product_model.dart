import 'dart:convert';

class Product {
  final String barcode;
  final String name;
  final String brand;
  final String? imageUrl;
  final String? category;
  final String? quantity;
  final double? ownerPriceUsd;
  final String? expiryDate;
  final double? lastPriceUsd;
  final DateTime? savedAt;
  final bool isPartialMatch;

  const Product({
    required this.barcode,
    required this.name,
    required this.brand,
    this.imageUrl,
    this.category,
    this.quantity,
    this.ownerPriceUsd,
    this.expiryDate,
    this.lastPriceUsd,
    this.savedAt,
    this.isPartialMatch = false,
  });

  bool get hasOwnerPrice => ownerPriceUsd != null && ownerPriceUsd! > 0;

  Product copyWith({
    String? barcode,
    String? name,
    String? brand,
    String? imageUrl,
    String? category,
    String? quantity,
    double? ownerPriceUsd,
    String? expiryDate,
    double? lastPriceUsd,
    DateTime? savedAt,
    bool? isPartialMatch,
  }) {
    return Product(
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      ownerPriceUsd: ownerPriceUsd ?? this.ownerPriceUsd,
      expiryDate: expiryDate ?? this.expiryDate,
      lastPriceUsd: lastPriceUsd ?? this.lastPriceUsd,
      savedAt: savedAt ?? this.savedAt,
      isPartialMatch: isPartialMatch ?? this.isPartialMatch,
    );
  }

  Map<String, dynamic> toJson() => {
        'barcode': barcode,
        'name': name,
        'brand': brand,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (category != null) 'category': category,
        if (quantity != null) 'quantity': quantity,
        if (ownerPriceUsd != null) 'ownerPriceUsd': ownerPriceUsd,
        if (expiryDate != null) 'expiryDate': expiryDate,
        if (lastPriceUsd != null) 'lastPriceUsd': lastPriceUsd,
        if (savedAt != null) 'savedAt': savedAt!.toIso8601String(),
      };

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        barcode: json['barcode'] as String,
        name: json['name'] as String,
        brand: json['brand'] as String,
        imageUrl: json['imageUrl'] as String?,
        category: json['category'] as String?,
        quantity: json['quantity'] as String?,
        ownerPriceUsd: (json['ownerPriceUsd'] as num?)?.toDouble(),
        expiryDate: json['expiryDate'] as String?,
        lastPriceUsd: (json['lastPriceUsd'] as num?)?.toDouble(),
        savedAt: json['savedAt'] != null
            ? DateTime.tryParse(json['savedAt'] as String)
            : null,
      );

  String toJsonString() => jsonEncode(toJson());
  factory Product.fromJsonString(String s) => Product.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
