import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../layout/bottom_menu_with_siri.dart';

class FiatCurrenciesScreen extends StatelessWidget {
  const FiatCurrenciesScreen({Key? key}) : super(key: key);

  Future<void> _saveSelectedCurrency(BuildContext context, String currency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_currency', currency);
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> currencies = [
      {
        'code': 'USD',
        'symbol': '\$',
        'flag': 'assets/images/us.png',
        'country': 'United States',
        'fullName': 'US Dollar',
      },
      {
        'code': 'CAD',
        'symbol': 'CA',
        'flag': 'assets/images/ca.png',
        'country': 'Canada',
        'fullName': 'Canadian Dollar',
      },
      {
        'code': 'AUD',
        'symbol': 'AU',
        'flag': 'assets/images/au.png',
        'country': 'Australia',
        'fullName': 'Australian Dollar',
      },
      {
        'code': 'GBP',
        'symbol': '£',
        'flag': 'assets/images/gb.png',
        'country': 'United Kingdom',
        'fullName': 'Pound Sterling',
      },
      {
        'code': 'EUR',
        'symbol': '€',
        'flag': 'assets/images/eu.png',
        'country': 'European Union',
        'fullName': 'Euro',
      },
      {
        'code': 'KWD',
        'symbol': 'KD',
        'flag': 'assets/images/kw.png',
        'country': 'Kuwait',
        'fullName': 'Kuwaiti Dinar',
      },
      {
        'code': 'TRY',
        'symbol': '₺',
        'flag': 'assets/images/tr.png',
        'country': 'Turkey',
        'fullName': 'Turkish Lira',
      },
      {
        'code': 'SAR',
        'symbol': '﷼',
        'flag': 'assets/images/sa.png',
        'country': 'Saudi Arabia',
        'fullName': 'Saudi Riyal',
      },
      {
        'code': 'CNY',
        'symbol': '¥',
        'flag': 'assets/images/cn.png',
        'country': 'China',
        'fullName': 'Chinese Yuan',
      },
      {
        'code': 'KRW',
        'symbol': '₩',
        'flag': 'assets/images/kr.png',
        'country': 'South Korea',
        'fullName': 'South Korean Won',
      },
      {
        'code': 'JPY',
        'symbol': '¥',
        'flag': 'assets/images/jp.png',
        'country': 'Japan',
        'fullName': 'Japanese Yen',
      },
      {
        'code': 'INR',
        'symbol': '₹',
        'flag': 'assets/images/in.png',
        'country': 'India',
        'fullName': 'Indian Rupee',
      },
      {
        'code': 'RUB',
        'symbol': '₽',
        'flag': 'assets/images/ru.png',
        'country': 'Russia',
        'fullName': 'Russian Ruble',
      },
      {
        'code': 'IQD',
        'symbol': 'ع.د',
        'flag': 'assets/images/iq.png',
        'country': 'Iraq',
        'fullName': 'Iraqi Dinar',
      },
      {
        'code': 'TND',
        'symbol': 'د.ت',
        'flag': 'assets/images/tn.png',
        'country': 'Tunisia',
        'fullName': 'Tunisian Dinar',
      },
      {
        'code': 'BHD',
        'symbol': 'ب.د',
        'flag': 'assets/images/bh.png',
        'country': 'Bahrain',
        'fullName': 'Bahraini Dinar',
      },
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Fiat Currencies',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            const Text(
              'All currency:',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xCB838383),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: currencies.length,
                itemBuilder: (context, index) {
                  final currency = currencies[index];
                  return InkWell(
                    onTap: () async {
                      await _saveSelectedCurrency(context, currency['code']);
                      Navigator.pop(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Image.asset(
                            currency['flag'],
                            width: 28,
                            height: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '${currency['code']} (${currency['symbol']})',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        color: Colors.black,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      currency['fullName'],
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: Colors.black,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  currency['country'],
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const BottomMenuWithSiri(),
    );
  }
} 