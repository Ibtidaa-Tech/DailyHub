import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Currencies DailyHub can display. Amounts are stored as plain numbers; the
/// currency is a display setting, so switching it never changes your data.
class CurrencyInfo {
  final String code;
  final String symbol;
  final String name;
  final int decimals;
  final String locale; // grouping style
  const CurrencyInfo(this.code, this.symbol, this.name,
      {this.decimals = 2, this.locale = 'en_US'});
}

class Currencies {
  static const List<CurrencyInfo> all = [
    CurrencyInfo('INR', '₹', 'Indian Rupee', locale: 'en_IN'),
    CurrencyInfo('USD', '\$', 'US Dollar'),
    CurrencyInfo('EUR', '€', 'Euro'),
    CurrencyInfo('GBP', '£', 'British Pound'),
    CurrencyInfo('AED', 'AED ', 'UAE Dirham'),
    CurrencyInfo('SAR', 'SAR ', 'Saudi Riyal'),
    CurrencyInfo('QAR', 'QAR ', 'Qatari Riyal'),
    CurrencyInfo('KWD', 'KWD ', 'Kuwaiti Dinar', decimals: 3),
    CurrencyInfo('OMR', 'OMR ', 'Omani Rial', decimals: 3),
    CurrencyInfo('BHD', 'BHD ', 'Bahraini Dinar', decimals: 3),
    CurrencyInfo('PKR', 'Rs ', 'Pakistani Rupee'),
    CurrencyInfo('BDT', '৳', 'Bangladeshi Taka'),
    CurrencyInfo('NPR', 'Rs ', 'Nepalese Rupee'),
    CurrencyInfo('LKR', 'Rs ', 'Sri Lankan Rupee'),
    CurrencyInfo('CAD', 'CA\$', 'Canadian Dollar'),
    CurrencyInfo('AUD', 'A\$', 'Australian Dollar'),
    CurrencyInfo('NZD', 'NZ\$', 'New Zealand Dollar'),
    CurrencyInfo('SGD', 'S\$', 'Singapore Dollar'),
    CurrencyInfo('MYR', 'RM ', 'Malaysian Ringgit'),
    CurrencyInfo('IDR', 'Rp ', 'Indonesian Rupiah', decimals: 0),
    CurrencyInfo('THB', '฿', 'Thai Baht'),
    CurrencyInfo('PHP', '₱', 'Philippine Peso'),
    CurrencyInfo('VND', '₫', 'Vietnamese Dong', decimals: 0),
    CurrencyInfo('JPY', '¥', 'Japanese Yen', decimals: 0),
    CurrencyInfo('CNY', '¥', 'Chinese Yuan'),
    CurrencyInfo('KRW', '₩', 'South Korean Won', decimals: 0),
    CurrencyInfo('HKD', 'HK\$', 'Hong Kong Dollar'),
    CurrencyInfo('CHF', 'CHF ', 'Swiss Franc'),
    CurrencyInfo('SEK', 'kr ', 'Swedish Krona'),
    CurrencyInfo('NOK', 'kr ', 'Norwegian Krone'),
    CurrencyInfo('DKK', 'kr ', 'Danish Krone'),
    CurrencyInfo('PLN', 'zł ', 'Polish Zloty'),
    CurrencyInfo('TRY', '₺', 'Turkish Lira'),
    CurrencyInfo('RUB', '₽', 'Russian Ruble'),
    CurrencyInfo('ZAR', 'R ', 'South African Rand'),
    CurrencyInfo('NGN', '₦', 'Nigerian Naira'),
    CurrencyInfo('KES', 'KSh ', 'Kenyan Shilling'),
    CurrencyInfo('EGP', 'E£', 'Egyptian Pound'),
    CurrencyInfo('BRL', 'R\$', 'Brazilian Real'),
    CurrencyInfo('MXN', 'MX\$', 'Mexican Peso'),
    CurrencyInfo('ARS', 'AR\$', 'Argentine Peso'),
    CurrencyInfo('ILS', '₪', 'Israeli Shekel'),
  ];

  static CurrencyInfo byCode(String code) =>
      all.firstWhere((c) => c.code == code, orElse: () => all.first);

  static const Map<String, String> _byCountry = {
    'IN': 'INR', 'US': 'USD', 'GB': 'GBP', 'AE': 'AED', 'SA': 'SAR',
    'QA': 'QAR', 'KW': 'KWD', 'OM': 'OMR', 'BH': 'BHD', 'PK': 'PKR',
    'BD': 'BDT', 'NP': 'NPR', 'LK': 'LKR', 'CA': 'CAD', 'AU': 'AUD',
    'NZ': 'NZD', 'SG': 'SGD', 'MY': 'MYR', 'ID': 'IDR', 'TH': 'THB',
    'PH': 'PHP', 'VN': 'VND', 'JP': 'JPY', 'CN': 'CNY', 'KR': 'KRW',
    'HK': 'HKD', 'CH': 'CHF', 'SE': 'SEK', 'NO': 'NOK', 'DK': 'DKK',
    'PL': 'PLN', 'TR': 'TRY', 'RU': 'RUB', 'ZA': 'ZAR', 'NG': 'NGN',
    'KE': 'KES', 'EG': 'EGP', 'BR': 'BRL', 'MX': 'MXN', 'AR': 'ARS',
    'IL': 'ILS',
    // Euro area
    'DE': 'EUR', 'FR': 'EUR', 'IT': 'EUR', 'ES': 'EUR', 'NL': 'EUR',
    'BE': 'EUR', 'AT': 'EUR', 'IE': 'EUR', 'PT': 'EUR', 'FI': 'EUR',
    'GR': 'EUR', 'LU': 'EUR', 'SK': 'EUR', 'SI': 'EUR', 'LT': 'EUR',
    'LV': 'EUR', 'EE': 'EUR', 'CY': 'EUR', 'MT': 'EUR', 'HR': 'EUR',
  };

  /// Picks a currency from the phone's region; India by default.
  static String detect() {
    try {
      final loc = WidgetsBinding.instance.platformDispatcher.locale;
      final cc = (loc.countryCode ?? '').toUpperCase();
      return _byCountry[cc] ?? 'INR';
    } catch (_) {
      return 'INR';
    }
  }
}

/// Formats money in the user's chosen currency. Whole amounts drop the
/// decimals so the UI stays clean ("₹1,250" rather than "₹1,250.00").
class Money {
  static CurrencyInfo current = Currencies.all.first;

  static final Map<String, NumberFormat> _cache = {};

  static NumberFormat _fmt(int decimals, {bool compact = false}) {
    final key = '${current.code}-$decimals-$compact';
    return _cache.putIfAbsent(key, () {
      if (compact) {
        return NumberFormat.compactCurrency(
            locale: current.locale, symbol: current.symbol, decimalDigits: decimals);
      }
      return NumberFormat.currency(
          locale: current.locale, symbol: current.symbol, decimalDigits: decimals);
    });
  }

  static String format(num value, {bool sign = false, bool compact = false}) {
    final v = value.isFinite ? value.toDouble() : 0.0;
    final whole = (v - v.roundToDouble()).abs() < 0.005;
    final decimals = whole ? 0 : current.decimals;
    final abs = v.abs();
    String s;
    if (compact && abs >= 100000) {
      s = _fmt(1, compact: true).format(abs);
    } else {
      s = _fmt(decimals).format(abs);
    }
    if (v < 0) return '−$s';
    if (sign && v > 0) return '+$s';
    return s;
  }

  static String get symbol => current.symbol.trim();
}
