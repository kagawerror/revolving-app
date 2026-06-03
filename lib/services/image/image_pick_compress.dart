import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

/// Picks a photo (camera or gallery) and returns compressed JPEG bytes,
/// shrinking upload size/cost before it reaches Cloudinary.
class ImagePickCompress {
  final ImagePicker _picker;
  ImagePickCompress([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  Future<Uint8List?> pick({required ImageSource source}) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final compressed = await FlutterImageCompress.compressWithList(
      bytes,
      quality: 70,
      minWidth: 1280,
      minHeight: 1280,
      format: CompressFormat.jpeg,
    );
    return compressed;
  }
}
