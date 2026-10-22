/// A phone photo of a check is often several megabytes. The register accepts
/// that file, then stores a smaller JPEG so the sale record stays light.
const int checkPhotoHardMaxBytes = 30000000;

/// Soft ceiling for the JPEG kept on the order. Larger results try a
/// smaller pass before they are stored anyway.
const int checkPhotoStoredMaxBytes = 900000;

const String checkPhotoTooHeavyError =
    'La photo est trop lourde (30 Mo maximum).';

const String checkPhotoUnreadableError = 'Cette photo ne peut pas être lue.';

class CheckPhotoPass {
  const CheckPhotoPass(this.maxEdge, this.quality);

  /// Longest side, in pixels, of the stored JPEG.
  final int maxEdge;

  /// JPEG quality passed to the canvas encoder, from 0 to 1.
  final double quality;
}

/// First pass keeps the check number readable. Later passes shrink further
/// when the JPEG is still heavy.
const List<CheckPhotoPass> checkPhotoPasses = [
  CheckPhotoPass(2000, 0.85),
  CheckPhotoPass(1600, 0.72),
  CheckPhotoPass(1200, 0.6),
];

class CheckPhotoSize {
  const CheckPhotoSize(this.width, this.height);

  final int width;
  final int height;
}

/// Scales [width] × [height] so the longest side is at most [maxEdge].
/// A photo that is already smaller is left as it is. Zero or negative
/// input returns a zero size.
CheckPhotoSize checkPhotoOutputSize(int width, int height, int maxEdge) {
  if (width <= 0 || height <= 0 || maxEdge <= 0) {
    return const CheckPhotoSize(0, 0);
  }
  final longest = width > height ? width : height;
  if (longest <= maxEdge) return CheckPhotoSize(width, height);
  final scale = maxEdge / longest;
  var outWidth = (width * scale).round();
  var outHeight = (height * scale).round();
  if (outWidth < 1) outWidth = 1;
  if (outHeight < 1) outHeight = 1;
  return CheckPhotoSize(outWidth, outHeight);
}
