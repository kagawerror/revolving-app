import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/dashboard/presentation/dashboard_body.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';
import 'package:rev_app/features/requests/domain/request_status.dart';

FundRequest _request({
  RequestStatus status = RequestStatus.created,
  DateTime? createdAt,
  DateTime? releasedAt,
}) =>
    FundRequest(
      id: 'r1',
      companyId: 'c1',
      fundId: 'f1',
      createdByUid: 'u1',
      beneficiaryName: 'Maria Santos',
      amount: Money.fromCentavos(250000),
      purpose: 'Fuel reimbursement',
      proofImageUrl: 'https://example.test/proof.jpg',
      status: status,
      createdAt: createdAt,
      releasedAt: releasedAt,
    );

void main() {
  group('recentDateLine', () {
    test('shows created date alone when not yet released', () {
      final line = recentDateLine(
        _request(createdAt: DateTime(2026, 6, 5)),
      );

      expect(line, 'Created 5 Jun 2026');
    });

    test('appends released date once released', () {
      final line = recentDateLine(
        _request(
          status: RequestStatus.released,
          createdAt: DateTime(2026, 6, 5),
          releasedAt: DateTime(2026, 6, 7),
        ),
      );

      expect(line, 'Created 5 Jun 2026 · Released 7 Jun 2026');
    });

    test('returns null when the created timestamp is missing', () {
      final line = recentDateLine(_request());

      expect(line, isNull);
    });
  });
}
