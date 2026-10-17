import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/staff_role.dart';
import '../../core/permissions/permission_id.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/permission_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/widgets/app_card.dart';

/// Role × permission defaults for the active module (mock until API).
class PermissionsMatrixTab extends ConsumerStatefulWidget {
  const PermissionsMatrixTab({super.key});

  @override
  ConsumerState<PermissionsMatrixTab> createState() =>
      _PermissionsMatrixTabState();
}

class _PermissionsMatrixTabState extends ConsumerState<PermissionsMatrixTab> {
  /// When non-null, show toggles for this role only.
  StaffRole? _detailRole;

  /// Full matrix (legacy list) vs role cards home.
  bool _showAllMatrix = false;

  void _openRoleDetail(StaffRole role) {
    setState(() {
      _detailRole = role;
      _showAllMatrix = false;
    });
  }

  void _closeRoleDetail() => setState(() => _detailRole = null);

  void _openAllMatrix() {
    setState(() {
      _showAllMatrix = true;
      _detailRole = null;
    });
  }

  void _closeAllMatrix() => setState(() => _showAllMatrix = false);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final module = ref.watch(authProvider.select((a) => a.module));
    final settings = ref.watch(permissionSettingsProvider);

    final intro = Text(
      'Valeurs par rôle pour ce module. Les exceptions par employé sont dans Personnel → Gérer les droits.',
      style: AppTextStyles.caption(
        color: isDark ? AppColors.coolGray : AppColors.darkGray,
      ),
    );

    Widget body;
    if (_detailRole != null) {
      body = _RolePermissionBody(
        module: module,
        role: _detailRole!,
        settings: settings,
      );
    } else if (_showAllMatrix) {
      body = _AllRolesPermissionBody(
        module: module,
        settings: settings,
      );
    } else {
      body = _RoleCardsBody(
        module: module,
        settings: settings,
        onOpenRole: _openRoleDetail,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacing24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_detailRole != null) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 22),
                  tooltip: 'Retour aux fiches de rôle',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  onPressed: _closeRoleDetail,
                ),
                const SizedBox(width: AppConstants.spacing8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _detailRole != null
                          ? staffRoleDisplayLabel(_detailRole!)
                          : _showAllMatrix
                              ? 'Tous les droits'
                              : 'Droits',
                      style: AppTextStyles.h3(),
                    ),
                    if (_detailRole == null) ...[
                      const SizedBox(height: AppConstants.spacing8),
                      intro,
                    ] else ...[
                      const SizedBox(height: AppConstants.spacing4),
                      Text(
                        'Activez les droits par défaut de ce rôle.',
                        style: AppTextStyles.caption(
                          color: isDark
                              ? AppColors.coolGray
                              : AppColors.darkGray,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_detailRole == null && !_showAllMatrix)
                TextButton(
                  onPressed: _openAllMatrix,
                  child: const Text('Voir tous les droits'),
                ),
              if (_showAllMatrix)
                TextButton(
                  onPressed: _closeAllMatrix,
                  child: const Text('Retour aux fiches de rôle'),
                ),
            ],
          ),
          const SizedBox(height: AppConstants.spacing16),
          body,
        ],
      ),
    );
  }
}

// ── Compact switch (smaller visual, still tappable row) ───────────────

class _CompactSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CompactSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.78,
      alignment: Alignment.centerRight,
      child: Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        activeThumbColor: AppColors.primaryBlue,
      ),
    );
  }
}

class _PermissionToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PermissionToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacing8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.body(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ),
            ),
          ),
          _CompactSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ── Role cards grid ───────────────────────────────────────────────────

class _RoleCardsBody extends StatelessWidget {
  final ActiveModule module;
  final PermissionSettingsState settings;
  final void Function(StaffRole) onOpenRole;

  const _RoleCardsBody({
    required this.module,
    required this.settings,
    required this.onOpenRole,
  });

  int _enabledForRole(StaffRole role) {
    final map = settings.roleDefaults[module]![role]!;
    return PermissionId.values.where((p) => map[p] == true).length;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = PermissionId.values.length;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final twoCols = w >= 700;
        final gap = AppConstants.spacing12;
        final cardWidth = twoCols ? (w - gap) / 2 : w;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final role in StaffRole.values)
              SizedBox(
                width: cardWidth,
                child: AppCard(
                  onTap: () => onOpenRole(role),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacing16,
                    vertical: AppConstants.spacing8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              staffRoleDisplayLabel(role),
                              style: AppTextStyles.body(
                                color: isDark
                                    ? AppColors.warmWhite
                                    : AppColors.nearBlack,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_enabledForRole(role)}/$total activés',
                              style: AppTextStyles.caption(
                                color: isDark
                                    ? AppColors.coolGray
                                    : AppColors.darkGray,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 22,
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Single role detail ────────────────────────────────────────────────

class _RolePermissionBody extends ConsumerWidget {
  final ActiveModule module;
  final StaffRole role;
  final PermissionSettingsState settings;

  const _RolePermissionBody({
    required this.module,
    required this.role,
    required this.settings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.all(AppConstants.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in PermissionId.values)
            _PermissionToggleRow(
              label: permissionLabel(p),
              value: settings.roleDefaults[module]![role]![p] ?? false,
              onChanged: (v) => ref
                  .read(permissionSettingsProvider.notifier)
                  .setRoleDefault(module, role, p, v),
            ),
        ],
      ),
    );
  }
}

// ── Full matrix ───────────────────────────────────────────────────────

class _AllRolesPermissionBody extends ConsumerWidget {
  final ActiveModule module;
  final PermissionSettingsState settings;

  const _AllRolesPermissionBody({
    required this.module,
    required this.settings,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppCard(
      padding: const EdgeInsets.all(AppConstants.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final role in StaffRole.values) ...[
            Text(
              staffRoleDisplayLabel(role),
              style: AppTextStyles.body(
                color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppConstants.spacing8),
            for (final p in PermissionId.values)
              _PermissionToggleRow(
                label: permissionLabel(p),
                value: settings.roleDefaults[module]![role]![p] ?? false,
                onChanged: (v) => ref
                    .read(permissionSettingsProvider.notifier)
                    .setRoleDefault(module, role, p, v),
              ),
            const SizedBox(height: AppConstants.spacing16),
          ],
        ],
      ),
    );
  }
}
