import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'secure_storage.dart';

/// مدیریت زبان و محلی‌سازی برای تمام پلتفرم‌ها
class LocaleManager {
  static LocaleManager? _instance;
  static LocaleManager get instance => _instance ??= LocaleManager._();
  
  LocaleManager._();
  
  // زبان‌های پشتیبانی شده
  static const Map<String, Locale> supportedLocales = {
    'en': Locale('en', 'US'),
    'fa': Locale('fa', 'IR'),
    'tr': Locale('tr', 'TR'),
    'ar': Locale('ar', 'SA'),
    'ru': Locale('ru', 'RU'),
    'zh': Locale('zh', 'CN'),
    'ja': Locale('ja', 'JP'),
    'ko': Locale('ko', 'KR'),
    'es': Locale('es', 'ES'),
    'fr': Locale('fr', 'FR'),
    'de': Locale('de', 'DE'),
    'it': Locale('it', 'IT'),
    'pt': Locale('pt', 'BR'),
    'nl': Locale('nl', 'NL'),
    'pl': Locale('pl', 'PL'),
    'sv': Locale('sv', 'SE'),
    'da': Locale('da', 'DK'),
    'no': Locale('no', 'NO'),
    'fi': Locale('fi', 'FI'),
    'cs': Locale('cs', 'CZ'),
    'sk': Locale('sk', 'SK'),
    'hu': Locale('hu', 'HU'),
    'ro': Locale('ro', 'RO'),
    'bg': Locale('bg', 'BG'),
    'hr': Locale('hr', 'HR'),
    'sl': Locale('sl', 'SI'),
    'et': Locale('et', 'EE'),
    'lv': Locale('lv', 'LV'),
    'lt': Locale('lt', 'LT'),
    'mt': Locale('mt', 'MT'),
    'el': Locale('el', 'GR'),
    'he': Locale('he', 'IL'),
    'hi': Locale('hi', 'IN'),
    'th': Locale('th', 'TH'),
    'vi': Locale('vi', 'VN'),
    'id': Locale('id', 'ID'),
    'ms': Locale('ms', 'MY'),
    'tl': Locale('tl', 'PH'),
    'bn': Locale('bn', 'BD'),
    'ur': Locale('ur', 'PK'),
    'ne': Locale('ne', 'NP'),
    'si': Locale('si', 'LK'),
    'my': Locale('my', 'MM'),
    'km': Locale('km', 'KH'),
    'lo': Locale('lo', 'LA'),
    'mn': Locale('mn', 'MN'),
    'ka': Locale('ka', 'GE'),
    'hy': Locale('hy', 'AM'),
    'az': Locale('az', 'AZ'),
    'kk': Locale('kk', 'KZ'),
    'ky': Locale('ky', 'KG'),
    'tg': Locale('tg', 'TJ'),
    'uz': Locale('uz', 'UZ'),
    'tk': Locale('tk', 'TM'),
    'ps': Locale('ps', 'AF'),
    'sd': Locale('sd', 'PK'),
    'mr': Locale('mr', 'IN'),
    'gu': Locale('gu', 'IN'),
    'pa': Locale('pa', 'IN'),
    'or': Locale('or', 'IN'),
    'ta': Locale('ta', 'IN'),
    'te': Locale('te', 'IN'),
    'kn': Locale('kn', 'IN'),
    'ml': Locale('ml', 'IN'),
    'as': Locale('as', 'IN'),
    'sa': Locale('sa', 'IN'),
    'bo': Locale('bo', 'CN'),
    'ug': Locale('ug', 'CN'),
    'ii': Locale('ii', 'CN'),
    'za': Locale('za', 'CN'),
    'jv': Locale('jv', 'ID'),
    'su': Locale('su', 'ID'),
    'ceb': Locale('ceb', 'PH'),
    'war': Locale('war', 'PH'),
    'ilo': Locale('ilo', 'PH'),
    'pam': Locale('pam', 'PH'),
    'bik': Locale('bik', 'PH'),
    'hil': Locale('hil', 'PH'),
    'bcl': Locale('bcl', 'PH'),
    'cbk': Locale('cbk', 'PH'),
  };
  
  // زبان پیش‌فرض
  static const String defaultLanguage = 'en';
  static const Locale defaultLocale = Locale('en', 'US');
  
  // Callbacks
  Function(Locale)? _onLocaleChanged;
  
  /// مقداردهی اولیه
  Future<void> initialize({
    Function(Locale)? onLocaleChanged,
  }) async {
    _onLocaleChanged = onLocaleChanged;
    
    // بارگذاری زبان ذخیره شده
    await _loadSavedLocale();
    
    print('🌍 LocaleManager initialized');
  }
  
  /// دریافت زبان فعلی
  Future<Locale> getCurrentLocale() async {
    try {
      final languageCode = await SecureStorage.instance.getSecureData('current_language');
      if (languageCode != null && supportedLocales.containsKey(languageCode)) {
        return supportedLocales[languageCode]!;
      }
      return defaultLocale;
    } catch (e) {
      print('Error getting current locale: $e');
      return defaultLocale;
    }
  }
  
  /// تنظیم زبان جدید
  Future<void> setLocale(String languageCode) async {
    try {
      if (!supportedLocales.containsKey(languageCode)) {
        print('❌ Unsupported language: $languageCode');
        return;
      }
      
      final newLocale = supportedLocales[languageCode]!;
      
      // ذخیره زبان جدید
      await SecureStorage.instance.saveSecureData('current_language', languageCode);
      
      // فراخوانی callback
      _onLocaleChanged?.call(newLocale);
      
      print('🌍 Language changed to: $languageCode');
    } catch (e) {
      print('Error setting locale: $e');
    }
  }
  
  /// تنظیم زبان با Locale object
  Future<void> setLocaleFromLocale(Locale locale) async {
    try {
      final languageCode = '${locale.languageCode}_${locale.countryCode}';
      
      // پیدا کردن کد زبان مناسب
      String? foundLanguageCode;
      for (final entry in supportedLocales.entries) {
        if (entry.value.languageCode == locale.languageCode &&
            entry.value.countryCode == locale.countryCode) {
          foundLanguageCode = entry.key;
          break;
        }
      }
      
      if (foundLanguageCode != null) {
        await setLocale(foundLanguageCode);
      } else {
        print('❌ Unsupported locale: $locale');
      }
    } catch (e) {
      print('Error setting locale from Locale object: $e');
    }
  }
  
  /// دریافت لیست زبان‌های پشتیبانی شده
  List<Map<String, dynamic>> getSupportedLanguages() {
    final languages = <Map<String, dynamic>>[];
    
    for (final entry in supportedLocales.entries) {
      languages.add({
        'code': entry.key,
        'locale': entry.value,
        'name': _getLanguageName(entry.key),
        'nativeName': _getNativeLanguageName(entry.key),
      });
    }
    
    // مرتب‌سازی بر اساس نام انگلیسی
    languages.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    
    return languages;
  }
  
  /// دریافت نام زبان به انگلیسی
  String _getLanguageName(String languageCode) {
    const languageNames = {
      'en': 'English',
      'fa': 'Persian',
      'tr': 'Turkish',
      'ar': 'Arabic',
      'ru': 'Russian',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'it': 'Italian',
      'pt': 'Portuguese',
      'nl': 'Dutch',
      'pl': 'Polish',
      'sv': 'Swedish',
      'da': 'Danish',
      'no': 'Norwegian',
      'fi': 'Finnish',
      'cs': 'Czech',
      'sk': 'Slovak',
      'hu': 'Hungarian',
      'ro': 'Romanian',
      'bg': 'Bulgarian',
      'hr': 'Croatian',
      'sl': 'Slovenian',
      'et': 'Estonian',
      'lv': 'Latvian',
      'lt': 'Lithuanian',
      'mt': 'Maltese',
      'el': 'Greek',
      'he': 'Hebrew',
      'hi': 'Hindi',
      'th': 'Thai',
      'vi': 'Vietnamese',
      'id': 'Indonesian',
      'ms': 'Malay',
      'tl': 'Tagalog',
      'bn': 'Bengali',
      'ur': 'Urdu',
      'ne': 'Nepali',
      'si': 'Sinhala',
      'my': 'Burmese',
      'km': 'Khmer',
      'lo': 'Lao',
      'mn': 'Mongolian',
      'ka': 'Georgian',
      'hy': 'Armenian',
      'az': 'Azerbaijani',
      'kk': 'Kazakh',
      'ky': 'Kyrgyz',
      'tg': 'Tajik',
      'uz': 'Uzbek',
      'tk': 'Turkmen',
      'ps': 'Pashto',
      'sd': 'Sindhi',
      'mr': 'Marathi',
      'gu': 'Gujarati',
      'pa': 'Punjabi',
      'or': 'Odia',
      'ta': 'Tamil',
      'te': 'Telugu',
      'kn': 'Kannada',
      'ml': 'Malayalam',
      'as': 'Assamese',
      'sa': 'Sanskrit',
      'bo': 'Tibetan',
      'ug': 'Uyghur',
      'ii': 'Nuosu',
      'za': 'Zhuang',
      'jv': 'Javanese',
      'su': 'Sundanese',
      'ceb': 'Cebuano',
      'war': 'Waray',
      'ilo': 'Ilocano',
      'pam': 'Kapampangan',
      'bik': 'Bikol',
      'hil': 'Hiligaynon',
      'bcl': 'Central Bikol',
      'cbk': 'Chavacano',
    };
    
    return languageNames[languageCode] ?? languageCode.toUpperCase();
  }
  
  /// دریافت نام زبان به زبان محلی
  String _getNativeLanguageName(String languageCode) {
    const nativeNames = {
      'en': 'English',
      'fa': 'فارسی',
      'tr': 'Türkçe',
      'ar': 'العربية',
      'ru': 'Русский',
      'zh': '中文',
      'ja': '日本語',
      'ko': '한국어',
      'es': 'Español',
      'fr': 'Français',
      'de': 'Deutsch',
      'it': 'Italiano',
      'pt': 'Português',
      'nl': 'Nederlands',
      'pl': 'Polski',
      'sv': 'Svenska',
      'da': 'Dansk',
      'no': 'Norsk',
      'fi': 'Suomi',
      'cs': 'Čeština',
      'sk': 'Slovenčina',
      'hu': 'Magyar',
      'ro': 'Română',
      'bg': 'Български',
      'hr': 'Hrvatski',
      'sl': 'Slovenščina',
      'et': 'Eesti',
      'lv': 'Latviešu',
      'lt': 'Lietuvių',
      'mt': 'Malti',
      'el': 'Ελληνικά',
      'he': 'עברית',
      'hi': 'हिन्दी',
      'th': 'ไทย',
      'vi': 'Tiếng Việt',
      'id': 'Bahasa Indonesia',
      'ms': 'Bahasa Melayu',
      'tl': 'Tagalog',
      'bn': 'বাংলা',
      'ur': 'اردو',
      'ne': 'नेपाली',
      'si': 'සිංහල',
      'my': 'မြန်မာ',
      'km': 'ខ្មែរ',
      'lo': 'ລາວ',
      'mn': 'Монгол',
      'ka': 'ქართული',
      'hy': 'Հայերեն',
      'az': 'Azərbaycan',
      'kk': 'Қазақ',
      'ky': 'Кыргызча',
      'tg': 'Тоҷикӣ',
      'uz': 'Oʻzbekcha',
      'tk': 'Türkmençe',
      'ps': 'پښتو',
      'sd': 'سنڌي',
      'mr': 'मराठी',
      'gu': 'ગુજરાતી',
      'pa': 'ਪੰਜਾਬੀ',
      'or': 'ଓଡ଼ିଆ',
      'ta': 'தமிழ்',
      'te': 'తెలుగు',
      'kn': 'ಕನ್ನಡ',
      'ml': 'മലയാളം',
      'as': 'অসমীয়া',
      'sa': 'संस्कृतम्',
      'bo': 'བོད་ཡིག',
      'ug': 'ئۇيغۇرچە',
      'ii': 'ꆈꌠꉙ',
      'za': 'Vahcuengh',
      'jv': 'Basa Jawa',
      'su': 'Basa Sunda',
      'ceb': 'Bisaya',
      'war': 'Winaray',
      'ilo': 'Ilokano',
      'pam': 'Kapampangan',
      'bik': 'Bikol',
      'hil': 'Hiligaynon',
      'bcl': 'Bikol Sentral',
      'cbk': 'Chavacano',
    };
    
    return nativeNames[languageCode] ?? _getLanguageName(languageCode);
  }
  
  /// بارگذاری زبان ذخیره شده
  Future<void> _loadSavedLocale() async {
    try {
      final languageCode = await SecureStorage.instance.getSecureData('current_language');
      if (languageCode != null && supportedLocales.containsKey(languageCode)) {
        final locale = supportedLocales[languageCode]!;
        _onLocaleChanged?.call(locale);
        print('🌍 Loaded saved locale: $languageCode');
      }
    } catch (e) {
      print('Error loading saved locale: $e');
    }
  }
  
  /// دریافت تنظیمات محلی‌سازی برای MaterialApp
  static List<LocalizationsDelegate<dynamic>> getLocalizationsDelegates() {
    return [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];
  }
  
  /// دریافت لیست زبان‌های پشتیبانی شده برای MaterialApp
  static List<Locale> getSupportedLocalesList() {
    return supportedLocales.values.toList();
  }
  
  /// بررسی آیا زبان RTL است
  static bool isRTL(String languageCode) {
    const rtlLanguages = {
      'ar', 'fa', 'he', 'ur', 'ps', 'sd',
    };
    return rtlLanguages.contains(languageCode);
  }
  
  /// دریافت جهت متن بر اساس زبان
  static TextDirection getTextDirection(String languageCode) {
    return isRTL(languageCode) ? TextDirection.rtl : TextDirection.ltr;
  }
  
  /// دریافت تنظیمات محلی‌سازی برای زبان خاص
  static Map<String, dynamic> getLocaleSettings(String languageCode) {
    return {
      'isRTL': isRTL(languageCode),
      'textDirection': getTextDirection(languageCode),
      'locale': supportedLocales[languageCode] ?? defaultLocale,
    };
  }
  
  /// ذخیره تنظیمات زبان اضافی
  Future<void> saveLanguageSettings(Map<String, dynamic> settings) async {
    try {
      await SecureStorage.instance.saveSecureJson('language_settings', settings);
      print('💾 Language settings saved');
    } catch (e) {
      print('Error saving language settings: $e');
    }
  }
  
  /// بارگذاری تنظیمات زبان اضافی
  Future<Map<String, dynamic>?> getLanguageSettings() async {
    try {
      return await SecureStorage.instance.getSecureJson('language_settings');
    } catch (e) {
      print('Error loading language settings: $e');
      return null;
    }
  }
  
  /// پاک کردن تنظیمات زبان
  Future<void> clearLanguageSettings() async {
    try {
      await SecureStorage.instance.deleteSecureData('current_language');
      await SecureStorage.instance.deleteSecureData('language_settings');
      print('🗑️ Language settings cleared');
    } catch (e) {
      print('Error clearing language settings: $e');
    }
  }
} 