import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:retail_pos/core/theme/app_colors.dart';
import 'package:retail_pos/core/theme/app_text_styles.dart';

import '../api.dart';
import '../money.dart';
import '../widgets.dart';

/// The receipt picture: shop, payment confirmation, lines, and the cashier QR once paid.
class OrderReceipt extends StatelessWidget {
  const OrderReceipt({super.key, required this.request, required this.link});

  final RequestView request;
  final String link;

  @override
  Widget build(BuildContext context) {
    final rate = request.usdRate;
    final kindLabel = request.isQuote ? 'Devis' : 'Commande';
    return ColoredBox(
      color: AppColors.warmOffWhite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShopHeader(request: request),
          const SizedBox(height: 16),
          if (request.isPaid) ...[
            _PaidHero(request: request, link: link),
            const SizedBox(height: 16),
          ],
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$kindLabel ${request.number}',
                            style: AppTextStyles.h2(color: AppColors.nearBlack),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              DateFormat(
                                'd MMM yyyy à HH:mm',
                                'fr',
                              ).format(request.createdAt),
                              if (request.customerName.isNotEmpty)
                                request.customerName,
                            ].join(' · '),
                            style: AppTextStyles.caption(),
                          ),
                        ],
                      ),
                    ),
                    request.isPaid
                        ? const Pill(label: 'Payé', color: AppColors.deepGreen)
                        : const Pill(label: 'À payer', color: AppColors.amber),
                  ],
                ),
                const Divider(height: 28, color: Color(0xFFF0EEE9)),
                for (final line in request.lines) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(
                          '${line.quantity}×',
                          style: AppTextStyles.body(
                            color: AppColors.darkGray,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              line.name,
                              style: AppTextStyles.body(
                                color: AppColors.nearBlack,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (line.optionsLabel.isNotEmpty)
                              Text(
                                line.optionsLabel,
                                style: AppTextStyles.caption(),
                              ),
                          ],
                        ),
                      ),
                      DualPrice(htg: line.totalHtg, rate: rate, alignEnd: true),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (request.discountHtg > 0) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text('Remise', style: AppTextStyles.body()),
                      ),
                      Text(
                        '- ${Money.usdFromHtg(request.discountHtg, rate)}',
                        style: AppTextStyles.body(
                          color: AppColors.deepGreen,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                const Divider(height: 8, color: Color(0xFFF0EEE9)),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Total',
                        style: AppTextStyles.h2(color: AppColors.nearBlack),
                      ),
                    ),
                    DualPrice(
                      htg: request.totalHtg,
                      rate: rate,
                      large: true,
                      alignEnd: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (request.note.isNotEmpty) ...[
            const SizedBox(height: 12),
            Panel(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.edit_note_rounded,
                    size: 20,
                    color: AppColors.darkGray,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(request.note, style: AppTextStyles.body()),
                  ),
                ],
              ),
            ),
          ],
          if (!request.isPaid) ...[
            const SizedBox(height: 12),
            _Hint(
              icon: request.isQuote
                  ? Icons.mark_email_read_outlined
                  : Icons.groups_outlined,
              text: request.isQuote
                  ? 'La boutique a reçu ce devis. Payez-le pour le transformer en commande, '
                        'ou partagez le lien à la personne qui paiera.'
                  : 'Payez maintenant, ou partagez ce lien : n\'importe qui peut l\'ouvrir et payer, '
                        'en Haïti comme à l\'étranger.',
            ),
          ],
        ],
      ),
    );
  }
}

class _ShopHeader extends StatelessWidget {
  const _ShopHeader({required this.request});

  final RequestView request;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: request.shopSlug.isEmpty
          ? null
          : () => context.go('/${request.shopSlug}'),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: ProductPhoto(
                url: request.coverUrl,
                name: request.shopName,
                radius: 12,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.shopName,
                    style: AppTextStyles.h2(
                      color: AppColors.nearBlack,
                    ).copyWith(fontSize: 17),
                  ),
                  if (request.shopSlug.isNotEmpty)
                    Text(
                      'Voir la boutique',
                      style: AppTextStyles.caption(
                        color: AppColors.primaryBlue,
                      ).copyWith(fontWeight: FontWeight.w600),
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

class _PaidHero extends StatelessWidget {
  const _PaidHero({required this.request, required this.link});

  final RequestView request;
  final String link;

  @override
  Widget build(BuildContext context) {
    final method = switch (request.paymentMethod) {
      'card' => 'par carte',
      'moncash' => 'par MonCash',
      _ => '',
    };
    return Panel(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.deepGreen.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: AppColors.deepGreen,
              size: 34,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Paiement reçu',
            style: AppTextStyles.h1(
              color: AppColors.nearBlack,
            ).copyWith(fontSize: 22),
          ),
          const SizedBox(height: 4),
          Text(
            'Commande ${request.number} confirmée${method.isEmpty ? '' : ', payée $method'}.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body(
              color: AppColors.darkGray,
            ).copyWith(fontSize: 14),
          ),
          const SizedBox(height: 18),
          QrImageView(
            data: link,
            semanticsLabel: link,
            size: 168,
            backgroundColor: AppColors.white,
          ),
          const SizedBox(height: 10),
          Text(
            request.number,
            style: AppTextStyles.body(
              color: AppColors.nearBlack,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'La caisse scanne ce code pour retrouver la commande. Ce lien affiche le reçu.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption(),
          ),
          if (request.pickupNote.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.lightBlue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    size: 20,
                    color: AppColors.primaryBlue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Retrait',
                          style: AppTextStyles.body(
                            color: AppColors.primaryBlue,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          request.pickupNote,
                          style: AppTextStyles.body(color: AppColors.nearBlack),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightBlue,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body(
                color: AppColors.nearBlack,
              ).copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
