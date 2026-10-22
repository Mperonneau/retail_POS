import 'product_photo_pick.dart';

typedef CheckPhotoPicker = Future<PickedProductPhoto?> Function();

/// File picker for a check photo. Tests replace this so no file dialog opens.
CheckPhotoPicker checkPhotoPicker = pickCheckPhoto;
