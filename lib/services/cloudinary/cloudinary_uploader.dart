import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/error/failure.dart';
import '../../core/error/result.dart';

/// Uploads proof images to Cloudinary using an UNSIGNED preset.
/// No API secret is used — only the public cloud name + preset, which are safe in-app.
class CloudinaryUploader {
  final String cloudName;
  final String uploadPreset;
  final String folder;
  final http.Client client;

  CloudinaryUploader({
    required this.cloudName,
    required this.uploadPreset,
    required this.folder,
    http.Client? client,
  }) : client = client ?? http.Client();

  Future<Result<String>> uploadJpeg(Uint8List bytes) async {
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      return const Err(ValidationFailure('Image upload is not configured.'));
    }
    try {
      final uri =
          Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');
      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = uploadPreset
        ..fields['folder'] = folder
        ..files.add(http.MultipartFile.fromBytes('file', bytes,
            filename: 'proof.jpg'));
      final streamed =
          await client.send(request).timeout(const Duration(seconds: 30));
      final body = await streamed.stream
          .bytesToString()
          .timeout(const Duration(seconds: 30));
      if (streamed.statusCode != 200) {
        return Err(UnexpectedFailure('Upload failed (${streamed.statusCode}).'));
      }
      final url = (jsonDecode(body) as Map<String, dynamic>)['secure_url'] as String?;
      if (url == null || url.isEmpty) {
        return const Err(UnexpectedFailure('Upload returned no URL.'));
      }
      return Ok(url);
    } on TimeoutException {
      return const Err(UnexpectedFailure('Upload timed out. Please retry.'));
    } catch (e, st) {
      developer.log('cloudinary upload failed',
          name: 'cloudinary', error: e, stackTrace: st);
      return const Err(UnexpectedFailure('Could not upload the proof image.'));
    }
  }
}
