import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class BadgeWidget extends StatelessWidget {
  final String icon; // ej: 'alpha' o 'frog_god'
  final double size;

  const BadgeWidget({
    super.key,
    required this.icon,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/badges/$icon.svg',
      height: size,
    );
  }
}