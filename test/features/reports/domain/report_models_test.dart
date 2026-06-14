import 'package:flutter_test/flutter_test.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/reports/domain/report_models.dart';

void main() {
  test('ReplenishedLineRow value equality', () {
    final a = ReplenishedLineRow(
      approvedDate: DateTime(2026, 6, 10),
      fundName: 'AUDIT',
      beneficiaryName: 'D. Belbar',
      purpose: 'Laptop',
      amount: Money.fromCentavos(5000000),
      isPartial: false,
      remarks: '',
      replenishmentId: 'rep1',
    );
    final b = ReplenishedLineRow(
      approvedDate: DateTime(2026, 6, 10),
      fundName: 'AUDIT',
      beneficiaryName: 'D. Belbar',
      purpose: 'Laptop',
      amount: Money.fromCentavos(5000000),
      isPartial: false,
      remarks: '',
      replenishmentId: 'rep1',
    );
    expect(a, b);
    expect(a.amount.centavos, 5000000);
  });
}
