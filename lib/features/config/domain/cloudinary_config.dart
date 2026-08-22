import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Admin-managed Cloudinary configuration stored at `appConfig/cloudinary`.
///
/// Only NON-SECRET fields live here. `apiKey` is a public Cloudinary identifier
/// and is safe to persist; the Cloudinary API SECRET is NEVER stored or carried
/// by this model. `AppSecrets.*` remain the build-time fallback when the doc is
/// missing or a field is blank (see [resolveCloudinaryConfig]).
class CloudinaryConfig extends Equatable {
  final String cloudName;
  final String uploadPreset;
  final String signaturePreset;
  final String uploadFolder;
  final String signatureFolder;
  final String apiKey;
  final DateTime? updatedAt;
  final String updatedByUid;

  const CloudinaryConfig({
    required this.cloudName,
    required this.uploadPreset,
    this.signaturePreset = '',
    this.uploadFolder = '',
    this.signatureFolder = '',
    this.apiKey = '',
    this.updatedAt,
    this.updatedByUid = '',
  });

  /// A blank-but-valid instance — used as the loading/empty seed.
  static const CloudinaryConfig empty =
      CloudinaryConfig(cloudName: '', uploadPreset: '');

  factory CloudinaryConfig.fromMap(Map<String, dynamic> m) => CloudinaryConfig(
        cloudName: (m['cloudName'] ?? '') as String,
        uploadPreset: (m['uploadPreset'] ?? '') as String,
        signaturePreset: (m['signaturePreset'] ?? '') as String,
        uploadFolder: (m['uploadFolder'] ?? '') as String,
        signatureFolder: (m['signatureFolder'] ?? '') as String,
        apiKey: (m['apiKey'] ?? '') as String,
        updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
        updatedByUid: (m['updatedByUid'] ?? '') as String,
      );

  /// The 6 public string fields plus audit metadata. Used with
  /// `set(..., SetOptions(merge: true))`; there is no separate create map.
  Map<String, dynamic> toUpdateMap(String actorUid) => {
        'cloudName': cloudName,
        'uploadPreset': uploadPreset,
        'signaturePreset': signaturePreset,
        'uploadFolder': uploadFolder,
        'signatureFolder': signatureFolder,
        'apiKey': apiKey,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUid': actorUid,
      };

  /// The preset actually used for signature uploads: the dedicated one when set,
  /// otherwise the shared upload preset.
  String get signatureEffectivePreset =>
      signaturePreset.isNotEmpty ? signaturePreset : uploadPreset;

  CloudinaryConfig copyWith({
    String? cloudName,
    String? uploadPreset,
    String? signaturePreset,
    String? uploadFolder,
    String? signatureFolder,
    String? apiKey,
    DateTime? updatedAt,
    String? updatedByUid,
  }) =>
      CloudinaryConfig(
        cloudName: cloudName ?? this.cloudName,
        uploadPreset: uploadPreset ?? this.uploadPreset,
        signaturePreset: signaturePreset ?? this.signaturePreset,
        uploadFolder: uploadFolder ?? this.uploadFolder,
        signatureFolder: signatureFolder ?? this.signatureFolder,
        apiKey: apiKey ?? this.apiKey,
        updatedAt: updatedAt ?? this.updatedAt,
        updatedByUid: updatedByUid ?? this.updatedByUid,
      );

  @override
  List<Object?> get props => [
        cloudName,
        uploadPreset,
        signaturePreset,
        uploadFolder,
        signatureFolder,
        apiKey,
        updatedAt,
        updatedByUid,
      ];
}
