import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_notification_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/constants.dart';

/// Centered modal driven by [appNotificationProvider]. Rendered in [main.dart]
/// above the navigator so it stays visible over sheets, drawers, and scrims.
/// Does not use [Tooltip] (no Overlay ancestor in this layer).
class AppNotificationModal extends ConsumerWidget {
  const AppNotificationModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appNotificationProvider);
    if (data == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final surface = isDark ? AppColors.darkSurface : AppColors.white;
    final title = _titleForKind(data.kind);

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(appNotificationProvider.notifier).dismiss(),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.5),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              behavior: HitTestBehavior.deferToChild,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 440,
                  maxHeight: mq.size.height * 0.72,
                ),
                child: Material(
                      color: surface,
                      elevation: 12,
                      shadowColor: Colors.black.withValues(alpha: 0.25),
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusCard),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(
                              AppConstants.spacing16,
                              AppConstants.spacing16,
                              AppConstants.spacing8,
                              AppConstants.spacing12,
                            ),
                            decoration: BoxDecoration(
                              color: _headerTint(data.kind, isDark),
                              border: Border(
                                bottom: BorderSide(
                                  color: isDark
                                      ? AppColors.darkBorder
                                      : const Color(0xFFE8E8EE),
                                ),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _iconBg(data.kind, isDark),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    _icon(data.kind),
                                    size: 26,
                                    color: _iconColor(data.kind, isDark),
                                  ),
                                ),
                                const SizedBox(width: AppConstants.spacing12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: AppTextStyles.h3(
                                          color: isDark
                                              ? AppColors.warmWhite
                                              : AppColors.nearBlack,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'BizManager Haïti',
                                        style: AppTextStyles.caption(
                                          color: isDark
                                              ? AppColors.coolGray
                                              : AppColors.darkGray,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Semantics(
                                  label: 'Fermer',
                                  button: true,
                                  child: InkWell(
                                    onTap: () => ref
                                        .read(appNotificationProvider
                                            .notifier)
                                        .dismiss(),
                                    customBorder: const CircleBorder(),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 22,
                                        color: isDark
                                            ? AppColors.coolGray
                                            : AppColors.darkGray,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: mq.size.height * 0.42,
                            ),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(
                                AppConstants.spacing16,
                              ),
                              child: Text(
                                data.message,
                                style: AppTextStyles.body(
                                  color: isDark
                                      ? AppColors.warmWhite
                                      : AppColors.nearBlack,
                                ).copyWith(height: 1.45),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppConstants.spacing16,
                              0,
                              AppConstants.spacing16,
                              AppConstants.spacing16,
                            ),
                            child: FilledButton(
                              onPressed: () => ref
                                  .read(appNotificationProvider.notifier)
                                  .dismiss(),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                backgroundColor:
                                    _buttonColor(data.kind, isDark),
                                foregroundColor: _buttonForeground(
                                    data.kind, isDark),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusButton,
                                  ),
                                ),
                              ),
                              child: Text(
                                'OK',
                                style: AppTextStyles.button(
                                  color: _buttonForeground(
                                      data.kind, isDark),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
    );
  }

  static String _titleForKind(AppNotificationKind kind) {
    switch (kind) {
      case AppNotificationKind.success:
        return 'Réussi';
      case AppNotificationKind.info:
        return 'Notice';
      case AppNotificationKind.warning:
        return 'Warning';
      case AppNotificationKind.error:
        return 'Erreur';
    }
  }

  static Color _headerTint(AppNotificationKind kind, bool isDark) {
    switch (kind) {
      case AppNotificationKind.success:
        return isDark
            ? AppColors.deepGreen.withValues(alpha: 0.2)
            : AppColors.deepGreen.withValues(alpha: 0.08);
      case AppNotificationKind.info:
        return isDark
            ? AppColors.primaryBlue.withValues(alpha: 0.2)
            : AppColors.lightBlue;
      case AppNotificationKind.warning:
        return isDark
            ? AppColors.amber.withValues(alpha: 0.15)
            : AppColors.amber.withValues(alpha: 0.1);
      case AppNotificationKind.error:
        return isDark
            ? AppColors.boldRed.withValues(alpha: 0.2)
            : AppColors.boldRed.withValues(alpha: 0.08);
    }
  }

  static Color _iconBg(AppNotificationKind kind, bool isDark) {
    switch (kind) {
      case AppNotificationKind.success:
        return AppColors.deepGreen.withValues(alpha: isDark ? 0.25 : 0.12);
      case AppNotificationKind.info:
        return AppColors.primaryBlue.withValues(alpha: isDark ? 0.25 : 0.12);
      case AppNotificationKind.warning:
        return AppColors.amber.withValues(alpha: isDark ? 0.25 : 0.15);
      case AppNotificationKind.error:
        return AppColors.boldRed.withValues(alpha: isDark ? 0.25 : 0.12);
    }
  }

  static Color _buttonColor(AppNotificationKind kind, bool isDark) {
    switch (kind) {
      case AppNotificationKind.success:
        return isDark ? AppColors.mediumGreen : AppColors.deepGreen;
      case AppNotificationKind.info:
        return isDark ? AppColors.skyBlue : AppColors.primaryBlue;
      case AppNotificationKind.warning:
        return AppColors.amber;
      case AppNotificationKind.error:
        return isDark ? AppColors.coralRed : AppColors.boldRed;
    }
  }

  static Color _buttonForeground(AppNotificationKind kind, bool isDark) {
    if (kind == AppNotificationKind.warning) {
      return AppColors.nearBlack;
    }
    return AppColors.white;
  }

  static Color _iconColor(AppNotificationKind kind, bool isDark) {
    switch (kind) {
      case AppNotificationKind.success:
        return isDark ? AppColors.mediumGreen : AppColors.deepGreen;
      case AppNotificationKind.info:
        return isDark ? AppColors.skyBlue : AppColors.primaryBlue;
      case AppNotificationKind.warning:
        return AppColors.amber;
      case AppNotificationKind.error:
        return isDark ? AppColors.coralRed : AppColors.boldRed;
    }
  }

  static IconData _icon(AppNotificationKind kind) {
    switch (kind) {
      case AppNotificationKind.success:
        return Icons.check_circle_outline_rounded;
      case AppNotificationKind.info:
        return Icons.info_outline_rounded;
      case AppNotificationKind.warning:
        return Icons.warning_amber_rounded;
      case AppNotificationKind.error:
        return Icons.error_outline_rounded;
    }
  }
}
