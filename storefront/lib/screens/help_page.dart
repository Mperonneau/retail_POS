import 'package:flutter/material.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  static const _topics = [
    (
      title: 'Trouver une boutique',
      body: 'L\'accueil liste les boutiques dont la vitrine est activée. Filtrez par département ou cherchez un nom, une ville.',
    ),
    (
      title: 'Devis ou commande',
      body:
          'Un devis est une demande de prix : la boutique la reçoit et le lien peut être payé plus tard. Une commande est à payer tout de suite, ou à envoyer à quelqu\'un qui paie.',
    ),
    (
      title: 'Payer',
      body:
          'Carte : facture en dollars US, avec une seule ligne de frais. MonCash : facture en gourdes, sans montant en dollars. Le paiement n\'est confirmé que par Stripe ou MonCash.',
    ),
    (
      title: 'Favoris et compte',
      body:
          'Le cœur enregistre une boutique sur cet appareil. Le compte relie vos demandes à votre numéro pour les revoir plus tard.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
      children: [
        Text('Aide', style: AppTextStyles.h1(color: AppColors.nearBlack)),
        const SizedBox(height: 12),
        for (final topic in _topics)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(topic.title, style: AppTextStyles.h2(color: AppColors.nearBlack).copyWith(fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(topic.body, style: AppTextStyles.body(color: AppColors.darkGray)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
