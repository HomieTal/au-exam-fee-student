import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Top-anchored notification panel that slides down from under the app bar
/// and auto-dismisses. Rendered as a root overlay entry, so it stays visible
/// above the keyboard — unlike SnackBars, which the keyboard pushes
/// off-screen.
class AppToast {
  AppToast._();

  static OverlayEntry? _active;
  static Timer? _timer;

  /// [error] shows red, [success] green, otherwise AU maroon.
  static void show(
    BuildContext context,
    String message, {
    bool error = false,
    bool success = false,
  }) {
    final color = error
        ? AppTheme.errorColor
        : success
            ? AppTheme.successColor
            : AppTheme.primaryColor;
    final icon = error
        ? Icons.error_outline_rounded
        : success
            ? Icons.check_circle_outline_rounded
            : Icons.info_outline_rounded;

    _timer?.cancel();
    _active?.remove();
    _active = null;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _TopToast(
        message: message,
        color: color,
        icon: icon,
        onDismiss: () {
          _timer?.cancel();
          if (_active == entry) _active = null;
          entry.remove();
        },
      ),
    );

    _active = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
    _timer = Timer(const Duration(seconds: 3), () {
      if (_active == entry) {
        _active = null;
        entry.remove();
      }
    });
  }
}

class _TopToast extends StatefulWidget {
  final String message;
  final Color color;
  final IconData icon;
  final VoidCallback onDismiss;

  const _TopToast({
    required this.message,
    required this.color,
    required this.icon,
    required this.onDismiss,
  });

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();

    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) _controller.reverse();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: SlideTransition(
          position: _slide,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x28000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(widget.icon, color: Colors.white, size: 21),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.message,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.3,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: widget.onDismiss,
                  child: const Icon(Icons.close_rounded,
                      size: 18, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
