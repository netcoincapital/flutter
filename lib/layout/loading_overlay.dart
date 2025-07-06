import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  const LoadingOverlay({Key? key, required this.isLoading}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isLoading) return const SizedBox.shrink();
    return Container(
      color: Colors.white.withOpacity(1.0),
      child: Center(
        child: Lottie.asset(
          'assets/animations/loading.json',
          width: 180,
          height: 180,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
} 