import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/staff_directory_entry.dart';
import '../../core/models/staff_role.dart';
import '../../core/providers/staff_directory_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../widgets/staff_editor_sheet.dart';
import '../widgets/staff_permission_panel.dart';

/// Staff directory. Opened from the sidebar, not from Paramètres.
class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key});

  void _openEditor(
    BuildContext context,
    bool isDark, {
    StaffDirectoryEntry? existing,
  }) {
    showAppBottomSheet(
      context: context,
      child: StaffEditorSheet(isDark: isDark, existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppColors.warmWhite : AppColors.primaryBlue;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spacing24,
            AppConstants.spacing24,
            AppConstants.spacing24,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Personnel', style: AppTextStyles.h1(color: titleColor)),
              const SizedBox(height: AppConstants.spacing16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Membres du personnel',
                      style: AppTextStyles.h3(),
                    ),
                  ),
                  AppButton(
                    label: 'Ajouter un employé',
                    onPressed: () => _openEditor(context, isDark),
                    icon: Icons.person_add_outlined,
                    fullWidth: false,
                    width: 130,
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacing8),
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Actifs'),
                  Tab(text: 'Inactifs'),
                ],
              ),
              const Divider(height: 1),
              const Expanded(
                child: TabBarView(
                  children: [
                    _StaffList(active: true),
                    _StaffList(active: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffList extends ConsumerWidget {
  const _StaffList({required this.active});

  final bool active;

  void _openEditor(
    BuildContext context,
    bool isDark, {
    StaffDirectoryEntry? existing,
  }) {
    showAppBottomSheet(
      context: context,
      child: StaffEditorSheet(isDark: isDark, existing: existing),
    );
  }

  void _showStaffOptions(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    StaffDirectoryEntry entry,
  ) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: false,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Modifier'),
              onTap: () {
                Navigator.pop(context);
                _openEditor(context, isDark, existing: entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('Gérer les droits'),
              onTap: () {
                Navigator.pop(context);
                showStaffPermissionPanel(context, entry);
              },
            ),
            ListTile(
              leading: Icon(
                entry.isActive
                    ? Icons.block_outlined
                    : Icons.check_circle_outline,
                color: entry.isActive ? AppColors.amber : AppColors.deepGreen,
              ),
              title: Text(entry.isActive ? 'Deactivate' : 'Activer'),
              onTap: () {
                ref
                    .read(staffDirectoryProvider.notifier)
                    .update(entry.copyWith(isActive: !entry.isActive));
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppColors.boldRed,
              ),
              title: const Text(
                'Retirer',
                style: TextStyle(color: AppColors.boldRed),
              ),
              onTap: () {
                ref.read(staffDirectoryProvider.notifier).remove(entry.id);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final staff = ref
        .watch(staffDirectoryProvider)
        .where((entry) => entry.isActive == active)
        .toList();

    if (staff.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppConstants.spacing24),
        child: Text(
          active ? 'Aucun employé actif' : 'Aucun employé inactif',
          style: AppTextStyles.body(
            color: isDark ? AppColors.coolGray : AppColors.darkGray,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(
        top: AppConstants.spacing16,
        bottom: AppConstants.spacing24,
      ),
      itemCount: staff.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppConstants.spacing8),
      itemBuilder: (_, i) {
        final s = staff[i];
        final initial = s.fullName.isNotEmpty ? s.fullName[0] : '?';
        return AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.1),
                child: Text(
                  initial.toUpperCase(),
                  style: AppTextStyles.body(
                    color: isDark ? AppColors.skyBlue : AppColors.primaryBlue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.fullName,
                      style: AppTextStyles.body(
                        color: isDark
                            ? AppColors.warmWhite
                            : AppColors.nearBlack,
                      ),
                    ),
                    Text(
                      '${staffRoleDisplayLabel(s.role)} · ${s.phone}',
                      style: AppTextStyles.caption(),
                    ),
                    Text(
                      s.email,
                      style: AppTextStyles.caption(
                        color: isDark ? AppColors.coolGray : AppColors.darkGray,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: s.isActive ? AppColors.deepGreen : AppColors.darkGray,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.more_vert, size: 18),
                onPressed: () => _showStaffOptions(context, ref, isDark, s),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      },
    );
  }
}
