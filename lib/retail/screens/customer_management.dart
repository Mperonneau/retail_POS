import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/mock/mock_retail_data.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/constants.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/section_header.dart';

class CustomerManagement extends ConsumerStatefulWidget {
  const CustomerManagement({super.key});

  @override
  ConsumerState<CustomerManagement> createState() => _CustomerManagementState();
}

class _CustomerManagementState extends ConsumerState<CustomerManagement> {
  MockCustomer? _selected;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(mockCustomersProvider).where((c) =>
        _search.isEmpty || c.name.toLowerCase().contains(_search.toLowerCase())).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.spacing24),
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 320, child: _buildList(customers, isDark)),
                  const SizedBox(width: AppConstants.spacing24),
                  if (_selected != null) Expanded(child: _buildDetail(_selected!, isDark)),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  children: [
                    _buildList(customers, isDark),
                    if (_selected != null) ...[
                      const SizedBox(height: AppConstants.spacing24),
                      _buildDetail(_selected!, isDark),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildList(List<MockCustomer> customers, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Clients', style: AppTextStyles.h1(color: isDark ? AppColors.warmWhite : AppColors.primaryBlue)),
        const SizedBox(height: AppConstants.spacing16),
        TextField(
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(
            hintText: 'Rechercher des clients...',
            prefixIcon: const Icon(Icons.search, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppConstants.radiusInput)),
            filled: true,
            fillColor: isDark ? AppColors.darkSurface : AppColors.white,
          ),
        ),
        const SizedBox(height: AppConstants.spacing16),
        ...customers.map((c) => Padding(
          padding: const EdgeInsets.only(bottom: AppConstants.spacing8),
          child: AppCard(
            onTap: () => setState(() => _selected = c),
            color: _selected?.id == c.id ? (isDark ? AppColors.primaryBlue.withValues(alpha: 0.12) : AppColors.lightBlue) : null,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, style: AppTextStyles.body(
                        color: isDark ? AppColors.warmWhite : AppColors.nearBlack,
                      ).copyWith(fontWeight: FontWeight.w600)),
                      Text(c.phone, style: AppTextStyles.caption()),
                    ],
                  ),
                ),
                if (c.outstandingBalance > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(CurrencyFormatter.local(context, c.outstandingBalance),
                          style: AppTextStyles.caption(color: AppColors.boldRed).copyWith(fontWeight: FontWeight.w700)),
                      Text('doit', style: AppTextStyles.caption()),
                    ],
                  ),
              ],
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildDetail(MockCustomer c, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name, style: AppTextStyles.h2(color: isDark ? AppColors.warmWhite : AppColors.nearBlack)),
              const SizedBox(height: 4),
              Text(c.phone, style: AppTextStyles.caption()),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacing16),
        Row(
          children: [
            Expanded(child: _CreditCard(label: 'Limite de crédit', value: CurrencyFormatter.local(context, c.creditLimit), color: AppColors.primaryBlue)),
            const SizedBox(width: 12),
            Expanded(child: _CreditCard(label: 'Impayé', value: CurrencyFormatter.local(context, c.outstandingBalance), color: c.outstandingBalance > 0 ? AppColors.boldRed : AppColors.deepGreen)),
          ],
        ),
        const SizedBox(height: AppConstants.spacing16),
        SectionHeader(title: 'Utilisation du crédit'),
        const SizedBox(height: AppConstants.spacing8),
        AppCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Utilisé', style: AppTextStyles.body()),
                  Text('${(c.outstandingBalance / c.creditLimit * 100).toStringAsFixed(0)}%',
                      style: AppTextStyles.body().copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: c.creditLimit > 0 ? c.outstandingBalance / c.creditLimit : 0,
                  backgroundColor: const Color(0xFFE0E0E0),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    c.outstandingBalance / c.creditLimit > 0.8 ? AppColors.boldRed : AppColors.primaryBlue,
                  ),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CreditCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _CreditCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Text(label, style: AppTextStyles.caption()),
          const SizedBox(height: 4),
          Text(value, style: AppTextStyles.price(color: color).copyWith(fontSize: 13), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
