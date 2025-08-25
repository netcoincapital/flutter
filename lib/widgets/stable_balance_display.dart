import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/crypto_token.dart';
import '../providers/price_provider.dart';
import '../providers/app_provider.dart';
import '../utils/shared_preferences_utils.dart';
import '../services/balance_display_manager.dart';
import '../services/balance_manager.dart';

/// Widget پایدار برای نمایش موجودی توکن‌ها در همه دستگاه‌ها
/// این widget از BalanceManager برای دریافت موجودی‌های پایدار استفاده می‌کند
class StableBalanceDisplay extends StatefulWidget {
  final CryptoToken token;
  final String userId;
  final bool isHidden;
  final VoidCallback? onTap;
  final double? customWidth;
  final bool showIcon;
  final bool showValue;
  final TextStyle? amountStyle;
  final TextStyle? valueStyle;

  const StableBalanceDisplay({
    Key? key,
    required this.token,
    required this.userId,
    this.isHidden = false,
    this.onTap,
    this.customWidth,
    this.showIcon = true,
    this.showValue = true,
    this.amountStyle,
    this.valueStyle,
  }) : super(key: key);

  @override
  State<StableBalanceDisplay> createState() => _StableBalanceDisplayState();
}

class _StableBalanceDisplayState extends State<StableBalanceDisplay>
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;
  
  @override
  void initState() {
    super.initState();
    // Listen to BalanceManager updates for automatic UI refresh
    BalanceManager.instance.addListener(_onBalanceUpdate);
  }
  
  @override
  void dispose() {
    BalanceManager.instance.removeListener(_onBalanceUpdate);
    super.dispose();
  }
  
  void _onBalanceUpdate() {
    if (mounted) {
      setState(() {
        // This will trigger a rebuild with updated balance data
      });
    }
  }

  /// دریافت موجودی پایدار از BalanceManager با fallback به token amount
  double get _stableBalance {
    // First try to get from BalanceManager
    final balanceFromManager = BalanceManager.instance.getTokenBalance(
      widget.userId,
      widget.token.symbol ?? '',
    );
    
    // If BalanceManager has valid data, use it
    if (balanceFromManager > 0.0) {
      return balanceFromManager;
    }
    
    // Fallback to token's own amount
    final amount = widget.token.amount;
    if (amount == null || amount.isNaN || amount.isInfinite) {
      return 0.0;
    }
    return amount < 0 ? 0.0 : amount;
  }

  /// فرمت‌بندی موجودی با در نظر گیری اندازه صفحه
  String get _formattedAmount {
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Create a copy of the token with the stable balance
    final tokenWithStableBalance = widget.token.copyWith(amount: _stableBalance);
    
    return BalanceDisplayManager.instance.getFormattedBalance(
      tokenWithStableBalance,
      widget.isHidden,
      screenWidth: screenWidth,
    );
  }



  /// فرمت‌بندی ارزش دلاری
  String _getFormattedValue(PriceProvider priceProvider) {
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Create a copy of the token with the stable balance
    final tokenWithStableBalance = widget.token.copyWith(amount: _stableBalance);
    
    return BalanceDisplayManager.instance.getFormattedValue(
      tokenWithStableBalance,
      priceProvider,
      widget.isHidden,
      screenWidth: screenWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Consumer<PriceProvider>(
      builder: (context, priceProvider, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = widget.customWidth ?? constraints.maxWidth;
            final isNarrow = availableWidth < 300;
            
            return Container(
              width: availableWidth,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12, 
                    vertical: 8
                  ),
                  child: _buildContent(isNarrow),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// ساخت محتوای widget بر اساس اندازه
  Widget _buildContent(bool isNarrow) {
    if (isNarrow) {
      return _buildNarrowLayout();
    } else {
      return _buildWideLayout();
    }
  }

  /// Layout برای صفحات کوچک
  Widget _buildNarrowLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showIcon) _buildTokenInfo(),
        const SizedBox(height: 4),
        _buildAmountRow(),
        if (widget.showValue) ...[
          const SizedBox(height: 2),
          _buildValueRow(),
        ],
      ],
    );
  }

  /// Layout برای صفحات بزرگ
  Widget _buildWideLayout() {
    return Row(
      children: [
        if (widget.showIcon) ...[
          _buildTokenIcon(),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTokenName(),
              if (widget.showValue) _buildValueRow(),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildAmountRow(),
          ],
        ),
      ],
    );
  }

  /// نمایش اطلاعات توکن
  Widget _buildTokenInfo() {
    return Row(
      children: [
        _buildTokenIcon(),
        const SizedBox(width: 8),
        Expanded(child: _buildTokenName()),
      ],
    );
  }

  /// آیکون توکن
  Widget _buildTokenIcon() {
    final symbol = (widget.token.symbol ?? '').toUpperCase();
    final assetIcons = {
      'BTC': 'assets/images/btc.png',
      'ETH': 'assets/images/ethereum_logo.png',
      'BNB': 'assets/images/binance_logo.png',
      'TRX': 'assets/images/tron.png',
      'USDT': 'assets/images/usdt.png',
      'USDC': 'assets/images/usdc.png',
      'MATIC': 'assets/images/pol.png',
      'SOL': 'assets/images/sol.png',
      'ADA': 'assets/images/cardano.png',
      'DOT': 'assets/images/dot.png',
      'AVAX': 'assets/images/avax.png',
      'XRP': 'assets/images/xrp.png',
    };

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: assetIcons[symbol] != null
            ? Image.asset(
                assetIcons[symbol]!,
                width: 32,
                height: 32,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => 
                    _buildFallbackIcon(),
              )
            : _buildFallbackIcon(),
      ),
    );
  }

  /// آیکون fallback
  Widget _buildFallbackIcon() {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.currency_bitcoin,
        size: 20,
        color: Colors.grey[600],
      ),
    );
  }

  /// نام توکن
  Widget _buildTokenName() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.token.name ?? 'Unknown',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '(${widget.token.symbol ?? 'UNK'})',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  /// نمایش موجودی
  Widget _buildAmountRow() {
    return Text(
      _formattedAmount,
      style: widget.amountStyle ??
          const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// نمایش ارزش
  Widget _buildValueRow() {
    if (!widget.showValue) return const SizedBox.shrink();
    
    return Consumer<PriceProvider>(
      builder: (context, priceProvider, child) {
        return Text(
          _getFormattedValue(priceProvider),
          style: widget.valueStyle ??
              TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

/// Widget برای نمایش ارزش کل پورتفولیو
class StableTotalValueDisplay extends StatelessWidget {
  final List<CryptoToken> tokens;
  final bool isHidden;
  final TextStyle? style;

  const StableTotalValueDisplay({
    Key? key,
    required this.tokens,
    this.isHidden = false,
    this.style,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<PriceProvider>(
      builder: (context, priceProvider, child) {
        final totalValue = BalanceDisplayManager.instance.calculateTotalPortfolioValue(tokens, priceProvider);
        final formattedValue = BalanceDisplayManager.instance.formatTotalPortfolioValue(totalValue, isHidden: isHidden);
        
        return Text(
          formattedValue,
          style: style ??
              const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
        );
      },
    );
  }


}
