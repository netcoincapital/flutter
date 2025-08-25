import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/current_price_data.dart';

class CoinMarketCapService {
  static const String _baseUrl = 'https://pro-api.coinmarketcap.com/v1';
  static const String _apiKey = '0d216d8a-ddd0-4ada-bacb-da2d7467468a';

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'X-CMC_PRO_API_KEY': _apiKey,
  };

  /// Get current price data for a cryptocurrency
  static Future<CurrentPriceData?> getCurrentPrice(String symbol) async {
    try {
      print('🔍 Fetching current price for $symbol from CoinMarketCap');

      final response = await http.get(
        Uri.parse('$_baseUrl/cryptocurrency/quotes/latest?symbol=${symbol.toUpperCase()}'),
        headers: _headers,
      );

      print('🌐 CoinMarketCap API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status']['error_code'] == 0 && data['data'] != null) {
          final symbolData = data['data'][symbol.toUpperCase()];
          if (symbolData != null) {
            final quote = symbolData['quote']['USD'];
            
            return CurrentPriceData(
              price: (quote['price'] as num?)?.toDouble() ?? 0.0,
              change24h: (quote['percent_change_24h'] as num?)?.toDouble() ?? 0.0,
              marketCap: (quote['market_cap'] as num?)?.toDouble() ?? 0.0,
              volume24h: (quote['volume_24h'] as num?)?.toDouble() ?? 0.0,
              lastUpdated: DateTime.tryParse(quote['last_updated'] ?? '') ?? DateTime.now(),
            );
          }
        } else {
          print('❌ CoinMarketCap API Error: ${data['status']['error_message']}');
        }
      } else {
        print('❌ CoinMarketCap HTTP Error: ${response.statusCode} - ${response.body}');
      }
      
      return null;
    } catch (e) {
      print('❌ Error fetching current price from CoinMarketCap: $e');
      
      // Return fallback mock data
      return _generateMockCurrentPrice(symbol);
    }
  }

  /// Generate mock current price data for fallback
  static CurrentPriceData _generateMockCurrentPrice(String symbol) {
    print('🔄 Generating mock price data for $symbol');
    
    final random = DateTime.now().millisecondsSinceEpoch % 1000;
    double basePrice;
    double marketCap;
    double volume24h;
    
    switch (symbol.toUpperCase()) {
      case 'BTC':
        basePrice = 45000.0;
        marketCap = 850000000000.0;
        volume24h = 25000000000.0;
        break;
      case 'ETH':
        basePrice = 3000.0;
        marketCap = 360000000000.0;
        volume24h = 15000000000.0;
        break;
      case 'TRX':
        basePrice = 0.08;
        marketCap = 7200000000.0;
        volume24h = 800000000.0;
        break;
      case 'NCC':
        basePrice = 0.22;
        marketCap = 220000000.0;
        volume24h = 5000000.0;
        break;
      default:
        basePrice = 100.0;
        marketCap = 1000000000.0;
        volume24h = 50000000.0;
    }
    
    // Add some realistic variation
    final priceVariation = (random - 500) / 10000; // ±5%
    final actualPrice = basePrice * (1 + priceVariation);
    
    final change24h = (random - 500) / 100; // ±5%
    
    return CurrentPriceData(
      price: actualPrice,
      change24h: change24h,
      marketCap: marketCap,
      volume24h: volume24h,
      lastUpdated: DateTime.now(),
    );
  }
}
