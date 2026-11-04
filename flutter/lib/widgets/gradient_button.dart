import 'package:flutter/material.dart';

import '../utils/design_tokens.dart';

/// 渐变大按钮：默认青绿渐变，可自定义渐变色与高度；onTap 传 null 即禁用。
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.startColor = kTeal,
    this.endColor = kTealDark,
    this.height = 64,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color startColor;
  final Color endColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusSM),
        onTap: onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[startColor, endColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(kRadiusSM),
            boxShadow: kShadowSm,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: Colors.white, size: kIconMD),
              const SizedBox(width: kSpaceXS),
              Text(
                label,
                style: const TextStyle(
                  fontSize: kFontLarge,
                  fontWeight: kWeightBold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
