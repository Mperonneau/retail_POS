import 'package:web/web.dart' as web;

void openPaymentUrl(String url) {
  web.window.open(url, '_blank');
}
