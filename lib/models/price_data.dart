import 'dart:convert';

/// Token price data model
class PriceData {
  final String? change24h;
  final String price;

  PriceData({
    this.change24h,
    required this.price,
  });

  factory PriceData.fromJson(Map<String, dynamic> json) {
    return PriceData(
      change24h: json['change_24h'] as String?,
      price: json['price'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'change_24h': change24h,
      'price': price,
    };
  }

  @override
  String toString() {
    return 'PriceData(change24h: $change24h, price: $price)';
  }
} 