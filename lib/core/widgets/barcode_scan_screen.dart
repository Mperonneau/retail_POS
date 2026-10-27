import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'app_close_button.dart';

/// 2D symbologies we never treat as a product barcode line.
bool _isBlockedProductBarcodeFormat(BarcodeFormat format) {
  return format == BarcodeFormat.qrCode ||
      format == BarcodeFormat.dataMatrix ||
      format == BarcodeFormat.pdf417 ||
      format == BarcodeFormat.aztec;
}

/// Modal camera barcode scanner. Use [showModal]; do not instantiate as a widget.
///
/// [mobile_scanner] supports Android, iOS, macOS, and Web only — not Linux or
/// Windows ([isSupported]).
class BarcodeScanScreen {
  BarcodeScanScreen._();

  static bool get isSupported {
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS =>
        true,
      _ => false,
    };
  }

  /// Opens a compact dialog with live camera preview (not a full-screen route).
  ///
  /// [acceptQr] also returns a QR code, so the register can open a vitrine receipt.
  static Future<String?> showModal(
    BuildContext context, {
    bool acceptQr = false,
  }) {
    if (!isSupported) return Future<String?>.value(null);
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) => _BarcodeScanDialog(acceptQr: acceptQr),
    );
  }
}

class _BarcodeScanDialog extends StatefulWidget {
  const _BarcodeScanDialog({required this.acceptQr});

  final bool acceptQr;

  @override
  State<_BarcodeScanDialog> createState() => _BarcodeScanDialogState();
}

class _BarcodeScanDialogState extends State<_BarcodeScanDialog> {
  late final MobileScannerController _controller;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    // Empty [formats] = detect all symbologies, then drop 2D in [_onDetect].
    // A strict whitelist caused "no response" when the engine reported
    // [BarcodeFormat.unknown] or a format not in the list (common on web).
    final CameraFacing facing;
    if (kIsWeb) {
      // Desktop browsers: usually "user" webcam only. Mobile browsers: use rear for product labels.
      facing = defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS
          ? CameraFacing.back
          : CameraFacing.front;
    } else {
      facing = CameraFacing.back;
    }
    _controller = MobileScannerController(
      formats: const <BarcodeFormat>[],
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: facing,
    );
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!mounted || _handled) return;
    for (final b in capture.barcodes) {
      final blocked = _isBlockedProductBarcodeFormat(b.format);
      if (blocked && !(widget.acceptQr && b.format == BarcodeFormat.qrCode)) {
        continue;
      }
      final value = (b.rawValue ?? b.displayValue)?.trim();
      if (value == null || value.isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop<String>(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.sizeOf(context);
    final maxW = min(420.0, mq.width - 40);
    final maxH = min(380.0, mq.height * 0.5);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: maxW,
        height: maxH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: theme.colorScheme.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    AppCloseButton(onPressed: () => Navigator.of(context).pop<String?>()),
                    Expanded(
                      child: Text(
                        'Scanner le code-barres',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    onDetectError: (error, stackTrace) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'La caméra est indisponible. Vous pouvez saisir le code.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      );
                    },
                  ),
                  // Guide: horizontal line with dimmed top/bottom so users align the barcode.
                  IgnorePointer(
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(color: Colors.black.withValues(alpha: 0.45)),
                        ),
                        Container(
                          height: 2,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                        Expanded(
                          child: Container(color: Colors.black.withValues(alpha: 0.45)),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          'Alignez le code-barres sur la ligne blanche.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ),
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
