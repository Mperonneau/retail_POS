import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/staff_directory_entry.dart';
import '../../core/permissions/default_role_permissions.dart';
import '../../core/permissions/permission_id.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/permission_settings_provider.dart';
import '../../core/providers/staff_session_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/widgets/app_close_button.dart';

/// Right-side panel: per-employee permission overrides.
class StaffPermissionPanel extends ConsumerWidget {
  final StaffDirectoryEntry entry;

  const StaffPermissionPanel({super.key, required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final module = ref.watch(authProvider.select((a) => a.module));
    final settings = ref.watch(permissionSettingsProvider);
    final session = ref.watch(staffSessionProvider);
    final base = settings.roleDefaults[module]?[entry.role] ??
        defaultPermissionsForRole(module, entry.role);
    final userOv = settings.userOverrides[entry.id] ?? {};
    final ownerPower = settings.ownerPowerIds.contains(entry.id);
    final canGrant = session != null &&
        (roleCanGrantOwnerPower(session.role) ||
            settings.ownerPowerIds.contains(session.employeeId));
    final showOwnerGrant = entry.role == StaffRole.seller && canGrant;

    return SafeArea(
      child: Material(
        color: isDark ? AppColors.darkSurface : AppColors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.spacing16,
                AppConstants.spacing8,
                AppConstants.spacing8,
                AppConstants.spacing8,
              ),
              child: Row(
                children: [
                  AppCloseButton(onPressed: () => Navigator.of(context).pop()),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Droits',
                          style: AppTextStyles.h3(
                            color: isDark
                                ? AppColors.warmWhite
                                : AppColors.primaryBlue,
                          ),
                        ),
                        Text(
                          entry.fullName,
                          style: AppTextStyles.caption(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          staffRoleDisplayLabel(entry.role),
                          style: AppTextStyles.caption(
                            color: isDark
                                ? AppColors.coolGray
                                : AppColors.darkGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppConstants.spacing16),
                children: [
                  Text(
                    'Activez pour remplacer le droit du rôle. Réinitialisez pour hériter.',
                    style: AppTextStyles.caption(
                      color: isDark ? AppColors.coolGray : AppColors.darkGray,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacing16),
                  if (showOwnerGrant) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Droits du propriétaire',
                        style: AppTextStyles.body(),
                      ),
                      subtitle: Text(
                        'Mêmes droits que le propriétaire. Un propriétaire ou un admin peut l\'activer.',
                        style: AppTextStyles.caption(
                          color: isDark ? AppColors.coolGray : AppColors.darkGray,
                        ),
                      ),
                      value: ownerPower,
                      activeThumbColor: AppColors.primaryBlue,
                      onChanged: (v) => ref
                          .read(permissionSettingsProvider.notifier)
                          .setOwnerPower(entry.id, v),
                    ),
                    const SizedBox(height: AppConstants.spacing8),
                  ],
                  for (final p in PermissionId.values)
                    _PermissionRow(
                      id: p,
                      module: module,
                      roleDefault: base[p] ?? false,
                      permissionOverride: ownerPower ? true : userOv[p],
                      locked: ownerPower,
                      onSetExplicit: (v) => ref
                          .read(permissionSettingsProvider.notifier)
                          .setUserOverride(entry.id, p, v),
                      onReset: () => ref
                          .read(permissionSettingsProvider.notifier)
                          .setUserOverride(entry.id, p, null),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacing16),
              child: OutlinedButton(
                onPressed: () {
                  final notifier =
                      ref.read(permissionSettingsProvider.notifier);
                  notifier.clearUserOverrides(entry.id);
                  notifier.setOwnerPower(entry.id, false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Exceptions effacées — les droits du rôle s\'appliquent')),
                    );
                  }
                },
                child: const Text('Effacer les exceptions'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final PermissionId id;
  final ActiveModule module;
  final bool roleDefault;
  final bool? permissionOverride;
  final bool locked;
  final ValueChanged<bool> onSetExplicit;
  final VoidCallback onReset;

  const _PermissionRow({
    required this.id,
    required this.module,
    required this.roleDefault,
    required this.permissionOverride,
    required this.onSetExplicit,
    required this.onReset,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final effective = permissionOverride ?? roleDefault;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacing4),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          permissionLabel(id, module: module),
          style: AppTextStyles.body(),
        ),
        subtitle: Text(
          locked
              ? 'Droit du propriétaire'
              : permissionOverride == null
                  ? 'Droit du rôle : ${roleDefault ? 'On' : 'Off'}'
                  : 'Exception personnalisée',
          style: AppTextStyles.caption(
            color: isDark ? AppColors.coolGray : AppColors.darkGray,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (permissionOverride != null && !locked)
              TextButton(
                onPressed: onReset,
                child: const Text('Réinitialiser'),
              ),
            Switch(
              value: effective,
              onChanged: locked ? null : (v) => onSetExplicit(v),
              activeThumbColor: AppColors.primaryBlue,
            ),
          ],
        ),
      ),
    );
  }
}

void showStaffPermissionPanel(BuildContext context, StaffDirectoryEntry entry) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fermer',
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, anim, sec) {
      return Align(
        alignment: Alignment.centerRight,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: Material(
            elevation: 12,
            child: SizedBox(
              width: AppConstants.sidePanelWidth(
                MediaQuery.of(ctx).size.width,
                (MediaQuery.of(ctx).size.width * 0.42).clamp(320.0, 440.0),
              ),
              height: MediaQuery.of(ctx).size.height,
              child: StaffPermissionPanel(entry: entry),
            ),
          ),
        ),
      );
    },
  );
}
