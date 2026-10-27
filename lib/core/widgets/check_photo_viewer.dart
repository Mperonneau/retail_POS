import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'app_close_button.dart';

/// Opens the check photo at the size of the screen. Pinch, double-tap, or the
/// buttons zoom in on the writing.
Future<void> showCheckPhoto(BuildContext context, Uint8List bytes) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fermer la photo',
    barrierColor: const Color(0xF2000000),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return CheckPhotoViewer(bytes: bytes);
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class CheckPhotoViewer extends StatefulWidget {
  final Uint8List bytes;

  const CheckPhotoViewer({super.key, required this.bytes});

  @override
  State<CheckPhotoViewer> createState() => _CheckPhotoViewerState();
}

class _CheckPhotoViewerState extends State<CheckPhotoViewer> {
  final TransformationController _transform = TransformationController();
  static const double _maxScale = 5;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  void _onTransform() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransform);
    _transform.dispose();
    super.dispose();
  }

  double get _scale => _transform.value.getMaxScaleOnAxis();

  void _setScale(double scale) {
    final box = context.findRenderObject() as RenderBox?;
    final size = box?.size ?? MediaQuery.sizeOf(context);
    final next = scale.clamp(1.0, _maxScale);
    final cx = size.width / 2;
    final cy = size.height / 2;
    _transform.value = Matrix4.identity()
      ..translateByDouble(cx, cy, 0, 1)
      ..scaleByDouble(next, next, 1, 1)
      ..translateByDouble(-cx, -cy, 0, 1);
  }

  void _zoomBy(double factor) => _setScale(_scale * factor);

  void _toggleZoom() => _setScale(_scale > 1.05 ? 1 : 2.5);

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('check-photo-viewer'),
      type: MaterialType.transparency,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onDoubleTap: _toggleZoom,
                    child: InteractiveViewer(
                      transformationController: _transform,
                      minScale: 1,
                      maxScale: _maxScale,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        child: Image.memory(
                          widget.bytes,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                            child: Text(
                              'Photo du chèque',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: AppCloseButton(
                key: const Key('check-photo-close'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ZoomButton(
                    key: const Key('check-photo-zoom-out'),
                    icon: Icons.zoom_out,
                    tooltip: 'Réduire',
                    onPressed: _scale <= 1.05 ? null : () => _zoomBy(1 / 1.6),
                  ),
                  const SizedBox(width: 12),
                  _ZoomButton(
                    key: const Key('check-photo-zoom-in'),
                    icon: Icons.zoom_in,
                    tooltip: 'Agrandir',
                    onPressed: _scale >= _maxScale - 0.05
                        ? null
                        : () => _zoomBy(1.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _ZoomButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: AppColors.nearBlack),
        tooltip: tooltip,
      ),
    );
  }
}

/// Small check photo. A tap opens [showCheckPhoto].
class CheckPhotoThumb extends StatelessWidget {
  final Uint8List bytes;
  final double height;
  final bool isDark;
  final Key photoKey;
  final String fallbackLabel;

  const CheckPhotoThumb({
    super.key,
    required this.bytes,
    required this.height,
    required this.isDark,
    required this.photoKey,
    this.fallbackLabel = 'Photo du chèque enregistrée',
  });

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.coolGray : AppColors.darkGray;
    final fill = isDark ? AppColors.darkBackground : const Color(0xFFF4F4F4);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: fill,
        child: InkWell(
          key: photoKey,
          onTap: () => showCheckPhoto(context, bytes),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Text(
                      fallbackLabel,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                ),
                const Positioned(
                  right: 6,
                  bottom: 6,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0x99000000),
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.zoom_in,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
