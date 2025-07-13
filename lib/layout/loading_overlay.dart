import 'package:flutter/material.dart';


class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  const LoadingOverlay({Key? key, required this.isLoading}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isLoading) return const SizedBox.shrink();
    return Container(
      color: Colors.white.withOpacity(1.0),
      child: Center(
        child: const CircularProgressIndicator(
          color: Colors.white,
        ),
      ),
    );
  }
} 