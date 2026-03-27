import 'package:flutter/material.dart';
import 'app_theme.dart';

class NfcPulseAnimation extends StatefulWidget {
  final double size;
  const NfcPulseAnimation({super.key, this.size = 200});

  @override
  State<NfcPulseAnimation> createState() => _NfcPulseAnimationState();
}

class _NfcPulseAnimationState extends State<NfcPulseAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              _buildRing(1.0, _controller.value),
              _buildRing(0.6, (_controller.value + 0.3) % 1.0),
              _buildRing(0.2, (_controller.value + 0.6) % 1.0),
              Container(
                width: widget.size * 0.4,
                height: widget.size * 0.4,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.nfc, color: Colors.white, size: 32),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRing(double startScale, double progress) {
    return Opacity(
      opacity: (1.0 - progress).clamp(0.0, 1.0),
      child: Container(
        width: widget.size * progress,
        height: widget.size * progress,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
