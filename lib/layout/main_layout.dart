import 'package:flutter/material.dart';
import 'dart:io';
import 'bottom_menu_with_siri.dart';

class MainLayout extends StatelessWidget {
  final Widget child;
  const MainLayout({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Remove bottom margin for iOS to move menu even lower
    final bottomMargin = Platform.isIOS ? 0.0 : 0.0;
    
    return Stack(
      children: [
        child,
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: EdgeInsets.only(bottom: bottomMargin),
            child: BottomMenuWithSiri(),
          ),
        ),
      ],
    );
  }
} 