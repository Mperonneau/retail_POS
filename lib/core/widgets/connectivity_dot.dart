import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

enum ConnectivityStatus { online, offline, syncing }

class ConnectivityDot extends StatefulWidget {
  final ConnectivityStatus status;
  final bool showLabel;

  const ConnectivityDot({
    super.key,
    this.status = ConnectivityStatus.online,
    this.showLabel = false,
  });

  @override
  State<ConnectivityDot> createState() => _ConnectivityDotState();
}

class _ConnectivityDotState extends State<ConnectivityDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(_animController);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Color get _dotColor {
    switch (widget.status) {
      case ConnectivityStatus.online:
        return AppColors.deepGreen;
      case ConnectivityStatus.offline:
        return AppColors.amber;
      case ConnectivityStatus.syncing:
        return AppColors.skyBlue;
    }
  }

  String get _label {
    switch (widget.status) {
      case ConnectivityStatus.online:
        return 'En ligne';
      case ConnectivityStatus.offline:
        return 'Hors ligne';
      case ConnectivityStatus.syncing:
        return 'Synchronisation...';
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget dot = widget.status == ConnectivityStatus.syncing
        ? AnimatedBuilder(
            animation: _animation,
            builder: (_, __) => Opacity(
              opacity: _animation.value,
              child: _buildDot(),
            ),
          )
        : _buildDot();

    if (!widget.showLabel) return dot;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 6),
        Text(_label, style: AppTextStyles.caption(color: _dotColor)),
      ],
    );
  }

  Widget _buildDot() => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
  );
}
