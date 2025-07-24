// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'crypto_token.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CryptoToken _$CryptoTokenFromJson(Map<String, dynamic> json) => CryptoToken(
      name: json['name'] as String?,
      symbol: json['symbol'] as String?,
      blockchainName: json['BlockchainName'] as String?,
      iconUrl: json['iconUrl'] as String? ??
          "https://coinceeper.com/defualtIcons/coin.png",
      isEnabled: json['isEnabled'] as bool,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      isToken: json['isToken'] as bool,
      smartContractAddress: json['SmartContractAddress'] as String?,
    );

Map<String, dynamic> _$CryptoTokenToJson(CryptoToken instance) =>
    <String, dynamic>{
      'name': instance.name,
      'symbol': instance.symbol,
      'BlockchainName': instance.blockchainName,
      'iconUrl': instance.iconUrl,
      'isEnabled': instance.isEnabled,
      'amount': instance.amount,
      'isToken': instance.isToken,
      'SmartContractAddress': instance.smartContractAddress,
    };

Asset _$AssetFromJson(Map<String, dynamic> json) => Asset(
      icon: (json['icon'] as num).toInt(),
      name: json['name'] as String,
      blockchainName: json['BlockchainName'] as String,
      amount: json['amount'] as String,
      value: json['value'] as String,
    );

Map<String, dynamic> _$AssetToJson(Asset instance) => <String, dynamic>{
      'icon': instance.icon,
      'name': instance.name,
      'BlockchainName': instance.blockchainName,
      'amount': instance.amount,
      'value': instance.value,
    };

SettingItemData _$SettingItemDataFromJson(Map<String, dynamic> json) =>
    SettingItemData(
      icon: (json['icon'] as num).toInt(),
      title: json['title'] as String,
      subtitle: json['subtitle'] as String?,
    );

Map<String, dynamic> _$SettingItemDataToJson(SettingItemData instance) =>
    <String, dynamic>{
      'icon': instance.icon,
      'title': instance.title,
      'subtitle': instance.subtitle,
    };

WalletResponse _$WalletResponseFromJson(Map<String, dynamic> json) =>
    WalletResponse(
      success: json['success'] as bool,
      phraseKey: json['PhraseKey'] as String?,
      message: json['message'] as String?,
    );

Map<String, dynamic> _$WalletResponseToJson(WalletResponse instance) =>
    <String, dynamic>{
      'success': instance.success,
      'PhraseKey': instance.phraseKey,
      'message': instance.message,
    };
