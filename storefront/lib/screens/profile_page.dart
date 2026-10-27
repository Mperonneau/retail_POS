import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';
import 'package:retail_pos/core/widgets/app_button.dart';
import 'package:retail_pos/core/widgets/app_input.dart';

import '../countries.dart';
import '../session.dart';
import '../widgets.dart';

String _accountLine(Session session) {
  final parts = <String>[
    if (session.phone.isNotEmpty) session.phone,
    if (countryName(session.country).isNotEmpty) countryName(session.country),
    if (session.email.isNotEmpty) session.email,
  ];
  return parts.join(' · ');
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Session.instance,
      builder: (context, _) {
        final session = Session.instance;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
          children: [
            Text('Profil', style: AppTextStyles.h1(color: AppColors.nearBlack)),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.lightBlue,
                  child: Icon(
                    session.isLoggedIn ? Icons.person_rounded : Icons.person_outline_rounded,
                    color: AppColors.primaryBlue,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.isLoggedIn ? session.name : 'Vous n\'êtes pas connecté',
                        style: AppTextStyles.h2(color: AppColors.nearBlack).copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        session.isLoggedIn
                            ? _accountLine(session)
                            : 'Connectez-vous pour retrouver vos commandes, ou continuez en invité.',
                        style: AppTextStyles.body(color: AppColors.darkGray),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (session.isLoggedIn) ...[
              AppButton(
                label: 'Modifier le nom',
                variant: AppButtonVariant.secondary,
                onPressed: () => _rename(context),
              ),
              const SizedBox(height: 8),
              AppButton(
                label: 'Se déconnecter',
                variant: AppButtonVariant.ghost,
                onPressed: session.logout,
              ),
            ] else
              AppButton(
                label: 'Se connecter',
                onPressed: () => context.push('/login'),
              ),
            const SizedBox(height: 24),
            _Menu(
              children: [
                _Row(icon: Icons.receipt_long_outlined, label: 'Mes commandes', onTap: () => context.go('/orders')),
                _Row(icon: Icons.favorite_border, label: 'Favoris', onTap: () => context.go('/favorites')),
                _Row(icon: Icons.shopping_bag_outlined, label: 'Panier', onTap: () => context.go('/cart')),
                _Row(icon: Icons.help_outline_rounded, label: 'Aide', onTap: () => context.push('/help')),
                _Row(icon: Icons.info_outline_rounded, label: 'À propos', onTap: () => context.push('/about')),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: Session.instance.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Votre nom'),
        content: AppInput(label: 'Nom', controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    try {
      await Session.instance.rename(name);
    } catch (e) {
      if (context.mounted) showToast(context, '$e', error: true);
    }
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primaryBlue),
      title: Text(label, style: AppTextStyles.body(color: AppColors.nearBlack)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
