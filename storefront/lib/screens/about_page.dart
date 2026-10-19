import 'package:flutter/material.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
      children: [
        Text('À propos', style: AppTextStyles.h1(color: AppColors.nearBlack)),
        const SizedBox(height: 12),
        Text(
          'La vitrine rassemble les boutiques. Vous parcourez le catalogue, vous demandez un devis ou vous commandez, puis vous payez par carte ou par MonCash.',
          style: AppTextStyles.body(color: AppColors.darkGray),
        ),
        const _Block(
          title: 'Avec ou sans compte',
          body:
              'Vous pouvez commander en invité. Un compte commence par votre numéro : un code est envoyé sur ce téléphone, et votre pays est enregistré avec le compte.',
        ),
        const _Block(
          title: 'Partager pour payer',
          body:
              'Chaque devis et chaque commande a un lien. Quelqu\'un d\'autre peut l\'ouvrir et payer, par exemple une commande créée en Haïti et réglée depuis les États-Unis.',
        ),
        const _Block(
          title: 'Deux façons de payer',
          body:
              'La carte affiche la facture en dollars US, frais compris. MonCash affiche la facture en gourdes seulement. La vente n\'est enregistrée qu\'une fois le paiement confirmé.',
        ),
        const _Block(
          title: 'Le retrait',
          body:
              'Après le paiement, la boutique indique où et comment retirer. Les prix sont montrés en dollars US, puis en gourdes.',
        ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.h2(color: AppColors.nearBlack).copyWith(fontSize: 18)),
          const SizedBox(height: 6),
          Text(body, style: AppTextStyles.body(color: AppColors.darkGray)),
        ],
      ),
    );
  }
}
