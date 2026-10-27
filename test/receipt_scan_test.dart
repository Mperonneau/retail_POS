import 'package:flutter_test/flutter_test.dart';
import 'package:retail_pos/retail/storefront/receipt_scan.dart';

void main() {
  test('a receipt link yields the request id', () {
    expect(
      storefrontRequestIdFromScan(
        'https://retail-pos-storefront.onrender.com/r/abc12345_XY-z',
      ),
      'abc12345_XY-z',
    );
    expect(storefrontRequestIdFromScan('/r/abc12345_XY-z'), 'abc12345_XY-z');
  });

  test('a product barcode is left alone', () {
    expect(storefrontRequestIdFromScan('37001111'), isNull);
    expect(storefrontRequestIdFromScan(''), isNull);
  });
}
