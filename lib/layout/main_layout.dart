import 'package:flutter/material.dart';
import 'dart:io';
import 'bottom_menu_with_siri.dart';

class MainLayout extends StatelessWidget {
  final Widget child;
  const MainLayout({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            minimum: EdgeInsets.zero, // No minimum padding - stick to bottom
            child: BottomMenuWithSiri(),
          ),
        ),
      ],
    );
  }
} 