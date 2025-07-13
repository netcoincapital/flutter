import 'package:flutter/material.dart';
import '../services/service_provider.dart';
import '../utils/shared_preferences_utils.dart';

class PriceProvider extends ChangeNotifier {
  final Map<String, Map<String, double>> _prices = {};
  bool _isLoading = false;
  String? _error;
  String _selectedCurrency = 'USD';

  Map<String, Map<String, double>> get prices => _prices;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedCurrency => _selectedCurrency;

  /// دریافت قیمت توکن‌ها (symbols) برای ارزهای مختلف (مطابق با Kotlin fetchPricesWithCache)
  Future<void> fetchPrices(List<String> symbols, {List<String>? currencies}) async {
    if (symbols.isEmpty) return;
    
    // اگر ارزها مشخص نشده، از ارز انتخابی استفاده کن
    final fiatCurrencies = currencies ?? [_selectedCurrency];
    
    print('🔄 PriceProvider: Starting to fetch prices for symbols: $symbols');
    print('🔄 PriceProvider: For currencies: $fiatCurrencies');
    
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      // ابتدا از کش بخوان (مطابق با Kotlin fetchPricesWithCache)
      final cachedPrices = await SharedPreferencesUtils.loadPricesMapFromCache(maxAgeMinutes: 5);
      bool useCachedData = false;
      
      if (cachedPrices != null) {
        // بررسی کن که آیا کش همه داده‌های مورد نیاز را دارد
        bool hasAllData = true;
        for (final symbol in symbols) {
          final upperSymbol = symbol.toUpperCase();
          if (!cachedPrices.containsKey(upperSymbol)) {
            hasAllData = false;
            break;
          }
          for (final currency in fiatCurrencies) {
            final upperCurrency = currency.toUpperCase();
            if (!cachedPrices[upperSymbol]!.containsKey(upperCurrency)) {
              hasAllData = false;
              break;
            }
          }
          if (!hasAllData) break;
        }
        
        if (hasAllData) {
          print('✅ PriceProvider: Using cached prices for all requested symbols');
          _prices.clear();
          _prices.addAll(cachedPrices);
          useCachedData = true;
        }
      }
      
      if (!useCachedData) {
        // کش ناقص یا منقضی شده، از API دریافت کن
        print('🌐 PriceProvider: Cache miss, fetching from API...');
        final apiService = ServiceProvider.instance.apiService;
        final response = await apiService.getPrices(symbols, fiatCurrencies);
        
        print('🔄 PriceProvider: API response received');
        print('🔄 PriceProvider: Response success: ${response.success}');
        
        if (response.success && response.prices != null) {
          _prices.clear();
          response.prices!.forEach((symbol, fiatMap) {
            print('🔄 PriceProvider: Processing symbol: $symbol');
            
            _prices[symbol.toUpperCase()] = {};
            fiatMap.forEach((currency, priceData) {
              if (priceData != null) {
                final price = double.tryParse(priceData.price.replaceAll(',', '')) ?? 0.0;
                _prices[symbol.toUpperCase()]![currency.toUpperCase()] = price;
                print('🔄 PriceProvider: Parsed price for $symbol in $currency: $price');
              }
            });
          });
          
          // ذخیره در کش (مطابق با Kotlin)
          await SharedPreferencesUtils.savePricesMapWithCache(_prices);
          print('💾 PriceProvider: Saved prices to cache');
        } else {
          _error = 'Failed to fetch prices';
          print('❌ PriceProvider: Failed to fetch prices');
        }
      }
    } catch (e) {
      _error = e.toString();
      print('❌ PriceProvider: Error fetching prices: $e');
    }
    
    _isLoading = false;
    notifyListeners();
    print('🔄 PriceProvider: Fetch completed. Final prices: $_prices');
  }

  /// دریافت قیمت برای ارز انتخابی
  double? getPrice(String symbol) {
    final symbolPrices = _prices[symbol.toUpperCase()];
    if (symbolPrices == null) return null;
    
    final price = symbolPrices[_selectedCurrency.toUpperCase()];
    print('💰 PriceProvider: Getting price for $symbol in $_selectedCurrency: $price');
    return price;
  }

  /// دریافت قیمت برای ارز خاص
  double? getPriceForCurrency(String symbol, String currency) {
    final symbolPrices = _prices[symbol.toUpperCase()];
    if (symbolPrices == null) return null;
    
    final price = symbolPrices[currency.toUpperCase()];
    print('💰 PriceProvider: Getting price for $symbol in $currency: $price');
    return price;
  }

  /// تغییر ارز انتخابی
  Future<void> setSelectedCurrency(String currency) async {
    _selectedCurrency = currency;
    await SharedPreferencesUtils.saveSelectedCurrency(currency);
    notifyListeners();
    print('🔄 PriceProvider: Selected currency changed to: $currency');
  }

  /// بارگذاری ارز انتخابی از SharedPreferences
  Future<void> loadSelectedCurrency() async {
    _selectedCurrency = await SharedPreferencesUtils.getSelectedCurrency();
    notifyListeners();
    print('🔄 PriceProvider: Loaded selected currency: $_selectedCurrency');
  }

  /// دریافت نماد ارز انتخابی
  String getCurrencySymbol() {
    return SharedPreferencesUtils.getCurrencySymbol(_selectedCurrency);
  }

  /// دریافت نماد ارز خاص
  String getCurrencySymbolForCurrency(String currency) {
    return SharedPreferencesUtils.getCurrencySymbol(currency);
  }

  /// تست مستقیم API برای debug
  Future<void> testApiResponse() async {
    print('🧪 PriceProvider: Testing API response...');
    try {
      final apiService = ServiceProvider.instance.apiService;
      final response = await apiService.getPrices(['BTC', 'ETH'], ['USD', 'EUR']);
      print('🧪 PriceProvider: Test response success: ${response.success}');
      print('🧪 PriceProvider: Test response prices: ${response.prices}');
      
      if (response.prices != null) {
        response.prices!.forEach((symbol, fiatMap) {
          print('🧪 PriceProvider: Test symbol: $symbol');
          print('🧪 PriceProvider: Test fiatMap: $fiatMap');
          fiatMap.forEach((currency, priceData) {
            print('🧪 PriceProvider: Test currency: $currency');
            print('🧪 PriceProvider: Test price data: $priceData');
            if (priceData != null) {
              print('🧪 PriceProvider: Test price string: ${priceData.price}');
              final price = double.tryParse(priceData.price.replaceAll(',', ''));
              print('🧪 PriceProvider: Test parsed price: $price');
            }
          });
        });
      }
    } catch (e) {
      print('❌ PriceProvider: Test error: $e');
    }
  }
} 