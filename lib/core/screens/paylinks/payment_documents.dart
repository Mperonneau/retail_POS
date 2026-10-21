import '../../mock/mock_retail_data.dart';
import '../../models/retail_order.dart';

/// A commande or a devis a payment link can be attached to.
enum PaymentDocumentKind { order, quote }

class PaymentDocument {
  const PaymentDocument({
    required this.id,
    required this.number,
    required this.kind,
    required this.totalHtg,
    this.clientName,
    this.clientPhone,
  });

  final String id;
  final String number;
  final PaymentDocumentKind kind;
  final double totalHtg;
  final String? clientName;
  final String? clientPhone;

  String get kindLabel =>
      kind == PaymentDocumentKind.order ? 'Commande' : 'Devis';

  bool get isQuote => kind == PaymentDocumentKind.quote;
}

/// Matches [query] against commande and devis numbers. An empty query matches nothing.
List<PaymentDocument> searchPaymentDocuments({
  required String query,
  required Iterable<RetailOrder> orders,
  required Iterable<MockRetailQuote> quotes,
}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  final hits = <PaymentDocument>[
    for (final order in orders)
      if (order.orderNumber.toLowerCase().contains(needle))
        PaymentDocument(
          id: order.id,
          number: order.orderNumber,
          kind: PaymentDocumentKind.order,
          totalHtg: order.totalHtg,
          clientName: order.clientName,
          clientPhone: order.clientPhone,
        ),
    for (final quote in quotes)
      if (quote.status != MockRetailQuoteStatus.cancelled &&
          quote.status != MockRetailQuoteStatus.converted &&
          quote.quoteNumber.toLowerCase().contains(needle))
        PaymentDocument(
          id: quote.id,
          number: quote.quoteNumber,
          kind: PaymentDocumentKind.quote,
          totalHtg: quote.totalBeforeTaxHtg(),
          clientName: quote.clientName,
          clientPhone: quote.clientPhone,
        ),
  ]..sort((a, b) => a.number.compareTo(b.number));
  if (hits.length <= 8) return hits;
  return hits.sublist(0, 8);
}
