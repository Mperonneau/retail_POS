import 'package:web/web.dart' as web;

void openReceiptUrl(String url) {
  if (url.startsWith('mailto:')) {
    web.window.location.assign(url);
    return;
  }
  web.window.open(url, '_blank');
}
