import 'package:flutter_test/flutter_test.dart';
import 'package:retail_pos/retail/widgets/check_photo_limits.dart';

void main() {
  test('a phone photo is scaled to the longest side of the pass', () {
    final landscape = checkPhotoOutputSize(4032, 3024, 2000);
    expect(landscape.width, 2000);
    expect(landscape.height, 1500);

    final portrait = checkPhotoOutputSize(3024, 4032, 2000);
    expect(portrait.width, 1500);
    expect(portrait.height, 2000);

    final alreadySmall = checkPhotoOutputSize(800, 600, 2000);
    expect(alreadySmall.width, 800);
    expect(alreadySmall.height, 600);

    final thin = checkPhotoOutputSize(100, 4000, 2000);
    expect(thin.width, 50);
    expect(thin.height, 2000);

    expect(checkPhotoOutputSize(0, 1200, 2000).width, 0);
  });

  test('the first pass keeps a readable check and stays under the old cap', () {
    expect(checkPhotoPasses.first.maxEdge, greaterThanOrEqualTo(1600));
    expect(checkPhotoHardMaxBytes, greaterThan(1500000));
    expect(checkPhotoStoredMaxBytes, lessThanOrEqualTo(1500000));
    expect(checkPhotoTooHeavyError.contains('1,5'), isFalse);
  });
}
