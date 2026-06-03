import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/money/money.dart';
import '../domain/fund_request.dart';
import '../domain/request_status.dart';
import 'request_providers.dart';

class CreateRequestController extends Notifier<bool> {
  @override
  bool build() => false; // submitting?

  Future<Result<String>> submit({
    required String companyId,
    required String fundId,
    required String createdByUid,
    required String beneficiary,
    required Money amount,
    required String purpose,
    required Uint8List? imageBytes,
  }) async {
    if (imageBytes == null) {
      return const Err(ValidationFailure('Attach a photo as proof of request.'));
    }
    if (amount == Money.zero) {
      return const Err(ValidationFailure('Enter an amount greater than zero.'));
    }
    state = true;
    try {
      final upload =
          await ref.read(cloudinaryUploaderProvider).uploadJpeg(imageBytes);
      final url = upload.valueOrNull;
      if (url == null) {
        return Err(upload.failureOrNull ??
            const UnexpectedFailure('Upload failed.'));
      }
      final request = FundRequest(
        id: '',
        companyId: companyId,
        fundId: fundId,
        createdByUid: createdByUid,
        beneficiaryName: beneficiary,
        amount: amount,
        purpose: purpose,
        proofImageUrl: url,
        status: RequestStatus.pendingAck,
      );
      return ref.read(requestRepositoryProvider).create(request);
    } finally {
      state = false;
    }
  }
}

final createRequestControllerProvider =
    NotifierProvider<CreateRequestController, bool>(CreateRequestController.new);
