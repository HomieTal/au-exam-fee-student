import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Shared decorative background for the auth screens: soft blue-grey canvas
/// with large translucent circles (matching the Admin App's login design).
class AuthBackground extends StatelessWidget {
  final Widget child;

  const AuthBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEDF1F9),
      child: Stack(
        children: [
          // Top-right circle
          Positioned(
            top: -80,
            right: -70,
            child: _circle(280, Colors.white.withValues(alpha: 0.55)),
          ),
          // Left-middle circle
          Positioned(
            top: 180,
            left: -110,
            child: _circle(240, const Color(0xFFDEE6F5).withValues(alpha: 0.8)),
          ),
          // Bottom-left circle
          Positioned(
            bottom: -60,
            left: -40,
            child: _circle(200, Colors.white.withValues(alpha: 0.45)),
          ),
          // Small bottom-right accent
          Positioned(
            bottom: 120,
            right: -60,
            child: _circle(160, const Color(0xFFDEE6F5).withValues(alpha: 0.6)),
          ),
          SafeArea(child: child),
        ],
      ),
    );
  }

  Widget _circle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// The white rounded-square logo badge with a soft shadow, as used on the
/// auth screens.
class AuthLogoBadge extends StatelessWidget {
  final double size;

  const AuthLogoBadge({super.key, this.size = 120});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF34506E).withValues(alpha: 0.14),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.2),
      child: Image.asset(
        'assets/images/anna_university_logo.png',
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Standard footer for auth screens: copyright + developer contact.
class AuthFooter extends StatelessWidget {
  const AuthFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          '© 2026 Anna University · CrackDevelopers',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Developer contact: ${AppConstants.developerEmail}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.textTheme.bodySmall?.color,
          ),
        ),
      ],
    );
  }
}
