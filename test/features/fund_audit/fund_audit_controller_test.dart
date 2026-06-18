import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

import 'package:rev_app/core/error/failure.dart';
import 'package:rev_app/core/error/result.dart';
import 'package:rev_app/core/money/money.dart';
import 'package:rev_app/features/auth/domain/app_user.dart';
import 'package:rev_app/features/auth/presentation/auth_providers.dart';
import 'package:rev_app/features/companies/domain/company.dart';
import 'package:rev_app/features/companies/domain/fund.dart';
import 'package:rev_app/features/companies/presentation/admin_providers.dart';
import 'package:rev_app/features/fund_audit/domain/denomination.dart';
import 'package:rev_app/features/fund_audit/domain/fund_audit.dart';
import 'package:rev_app/features/fund_audit/domain/fund_audit_repository.dart';
import 'package:rev_app/features/fund_audit/domain/ocr_text_service.dart';
import 'package:rev_app/features/fund_audit/presentation/fund_audit_providers.dart';
import 'package:rev_app/features/requests/domain/fund_request.dart';

class _MockRepo extends Mock implements FundAuditRepository {}

class _MockOcr extends Mock implements OcrTextService {}

class _MockPicker extends Mock implements ImagePicker {}

const _args = (companyId: 'c1', fundId: 'f1');

// effectiveBudget = originalBudget (90000) + adjustmentsCentavos (10000) =
// 100000, so the controller must read effectiveBudget, NOT originalBudget.
final _fund = Fund(
  id: 'f1',
  companyId: 'c1',
  name: 'Petty Cash',
  originalBudget: Money.fromCentavos(90000),
  availableBalance: Money.fromCentavos(70000),
  lowBalanceThresholdPct: 3,
  status: FundStatus.active,
  adjustmentsCentavos: 10000,
);

const _user = AppUser(
  uid: 'u1',
  companyId: 'c1',
  role: UserRole.incharge,
  displayName: 'Cathy Custodian',
  email: 'c@x.com',
  themeMode: ThemeMode.system,
);

ProviderContainer _container({
  required FundAuditRepository repo,
  OcrTextService? ocr,
  ImagePicker? picker,
}) {
  return ProviderContainer(overrides: [
    fundAuditRepositoryProvider.overrideWithValue(repo),
    if (ocr != null) ocrTextServiceProvider.overrideWithValue(ocr),
    if (picker != null) imagePickerProvider.overrideWithValue(picker),
    companyFundsProvider('c1').overrideWith((ref) => Stream.value([_fund])),
    companiesProvider
        .overrideWith((ref) => Stream.value(const [Company(id: 'c1', name: 'Acme')])),
    currentUserProvider.overrideWith((ref) => Stream.value(_user)),
  ]);
}

void main() {
  setUpAll(() {
    registerFallbackValue(ImageSource.camera);
    registerFallbackValue(FundAudit(
      id: '',
      companyId: '',
      fundId: '',
      fundName: '',
      companyName: '',
      custodianUid: '',
      custodianName: '',
      effectiveBudget: Money.zero,
      physicalCash: Money.zero,
      outstanding: Money.zero,
      varianceCentavos: 0,
      denominations: const [],
      proofImageUrl: '',
      note: '',
    ));
  });

  FundAuditRepository repoWithOutstanding(List<FundRequest> outstanding) {
    final repo = _MockRepo();
    when(() => repo.fetchOutstandingForFund(any(), any()))
        .thenAnswer((_) async => Ok(outstanding));
    return repo;
  }

  test('init snapshots fund name + effective budget', () async {
    final repo = repoWithOutstanding(const []);
    final c = _container(repo: repo);
    addTearDown(c.dispose);
    // Let companyFundsProvider stream resolve.
    await c.read(companyFundsProvider('c1').future);

    final state = c.read(fundAuditControllerProvider(_args));
    expect(state.fundName, 'Petty Cash');
    expect(state.effectiveBudget.centavos, 100000);
  });

  test('setCount recomputes the outcome variance', () async {
    final repo = repoWithOutstanding(const []);
    final c = _container(repo: repo);
    addTearDown(c.dispose);
    await c.read(companyFundsProvider('c1').future);

    // Keep the autoDispose notifier alive across awaits.
    final sub = c.listen(fundAuditControllerProvider(_args), (_, _) {});
    addTearDown(sub.close);

    final ctrl = c.read(fundAuditControllerProvider(_args).notifier);
    ctrl.setCount(Denomination.p100, 7); // 70000 physical
    // wait a microtask for the async outstanding load to settle
    await Future<void>.delayed(Duration.zero);

    final state = c.read(fundAuditControllerProvider(_args));
    expect(state.counts[Denomination.p100], 7);
    // budget 100000 - physical 70000 - outstanding 0 = 30000 short
    expect(state.outcome.varianceCentavos, 30000);
  });

  test('increment / decrement adjust the count and clamp at zero', () async {
    final repo = repoWithOutstanding(const []);
    final c = _container(repo: repo);
    addTearDown(c.dispose);
    await c.read(companyFundsProvider('c1').future);

    final ctrl = c.read(fundAuditControllerProvider(_args).notifier);
    ctrl.increment(Denomination.p50);
    ctrl.increment(Denomination.p50);
    ctrl.decrement(Denomination.p50);
    ctrl.decrement(Denomination.p50);
    ctrl.decrement(Denomination.p50); // would go negative

    final state = c.read(fundAuditControllerProvider(_args));
    expect(state.counts[Denomination.p50], 0);
  });

  test('pickPhotoAndOcr merges parsed counts and marks them ocrPrefilled',
      () async {
    final repo = repoWithOutstanding(const []);
    final ocr = _MockOcr();
    when(() => ocr.recognizeLines(any())).thenAnswer((_) async => const Ok([
          RecognizedLine('1000 x 2 = 2000'),
          RecognizedLine('100 x 5 = 500'),
        ]));
    final picker = _MockPicker();
    when(() => picker.pickImage(
          source: any(named: 'source'),
          maxWidth: any(named: 'maxWidth'),
        )).thenAnswer((_) async => XFile('/tmp/sheet.jpg'));

    final c = _container(repo: repo, ocr: ocr, picker: picker);
    addTearDown(c.dispose);
    await c.read(companyFundsProvider('c1').future);

    final ctrl = c.read(fundAuditControllerProvider(_args).notifier);
    await ctrl.pickPhotoAndOcr();

    final state = c.read(fundAuditControllerProvider(_args));
    expect(state.counts[Denomination.p1000], 2);
    expect(state.counts[Denomination.p100], 5);
    expect(state.ocrPrefilled, containsAll([Denomination.p1000, Denomination.p100]));
    expect(state.ocrRunning, isFalse);
    expect(state.ocrAttemptedNoMatch, isFalse);
    expect(state.proofImagePath, '/tmp/sheet.jpg');
  });

  test(
      'pickPhotoAndOcr fills the grid from COLUMN-segmented boxed fragments',
      () async {
    final repo = repoWithOutstanding(const []);
    final ocr = _MockOcr();
    // ML Kit emits the face-value column, then the count column (column-wise).
    // Boxes carry geometry so the controller's reconstructRows rebuilds rows.
    RecognizedLine frag(String t, double left, double right, double cY) =>
        RecognizedLine(t, box: TextBox(left, cY - 18, right, cY + 18));
    const faces = ['1.00', '5.00', '10.00', '50.00', '100.00', '1000.00'];
    const counts = ['8', '1', '1', '2', '2', '2'];
    final frags = <RecognizedLine>[
      for (var i = 0; i < faces.length; i++)
        frag(faces[i], 20, 90, 30 + i * 50),
      for (var i = 0; i < counts.length; i++)
        frag(counts[i], 200, 240, 30 + i * 50),
    ];
    when(() => ocr.recognizeLines(any())).thenAnswer((_) async => Ok(frags));
    final picker = _MockPicker();
    when(() => picker.pickImage(
          source: any(named: 'source'),
          maxWidth: any(named: 'maxWidth'),
        )).thenAnswer((_) async => XFile('/tmp/sheet.jpg'));

    final c = _container(repo: repo, ocr: ocr, picker: picker);
    addTearDown(c.dispose);
    await c.read(companyFundsProvider('c1').future);

    final ctrl = c.read(fundAuditControllerProvider(_args).notifier);
    await ctrl.pickPhotoAndOcr();

    final state = c.read(fundAuditControllerProvider(_args));
    expect(state.counts[Denomination.p1], 8);
    expect(state.counts[Denomination.p5], 1);
    expect(state.counts[Denomination.p10], 1);
    expect(state.counts[Denomination.p50], 2);
    expect(state.counts[Denomination.p100], 2);
    expect(state.counts[Denomination.p1000], 2);
    expect(state.ocrAttemptedNoMatch, isFalse);
    expect(state.proofImagePath, '/tmp/sheet.jpg');
  });

  test('pickPhotoAndOcr matched nothing: flags no-match, keeps photo + manual',
      () async {
    final repo = repoWithOutstanding(const []);
    final ocr = _MockOcr();
    RecognizedLine frag(String t, double left, double right, double cY) =>
        RecognizedLine(t, box: TextBox(left, cY - 18, right, cY + 18));
    when(() => ocr.recognizeLines(any())).thenAnswer((_) async => Ok([
          frag('hello', 20, 90, 30),
          frag('world', 200, 260, 30),
          frag('nonsense', 20, 90, 80),
        ]));
    final picker = _MockPicker();
    when(() => picker.pickImage(
          source: any(named: 'source'),
          maxWidth: any(named: 'maxWidth'),
        )).thenAnswer((_) async => XFile('/tmp/sheet.jpg'));

    final c = _container(repo: repo, ocr: ocr, picker: picker);
    addTearDown(c.dispose);
    await c.read(companyFundsProvider('c1').future);
    final sub = c.listen(fundAuditControllerProvider(_args), (_, _) {});
    addTearDown(sub.close);

    final ctrl = c.read(fundAuditControllerProvider(_args).notifier);
    await ctrl.pickPhotoAndOcr();

    var state = c.read(fundAuditControllerProvider(_args));
    expect(state.counts.values.where((v) => v > 0), isEmpty);
    expect(state.ocrPrefilled, isEmpty);
    expect(state.ocrAttemptedNoMatch, isTrue);
    expect(state.proofImagePath, '/tmp/sheet.jpg');

    // Manual entry still works after a no-match OCR.
    ctrl.setCount(Denomination.p50, 4);
    state = c.read(fundAuditControllerProvider(_args));
    expect(state.counts[Denomination.p50], 4);
  });

  test('OCR error leaves the grid editable (counts unchanged, not running)',
      () async {
    final repo = repoWithOutstanding(const []);
    final ocr = _MockOcr();
    when(() => ocr.recognizeLines(any()))
        .thenAnswer((_) async => const Err(UnexpectedFailure('bad')));
    final picker = _MockPicker();
    when(() => picker.pickImage(
          source: any(named: 'source'),
          maxWidth: any(named: 'maxWidth'),
        )).thenAnswer((_) async => XFile('/tmp/sheet.jpg'));

    final c = _container(repo: repo, ocr: ocr, picker: picker);
    addTearDown(c.dispose);
    await c.read(companyFundsProvider('c1').future);

    final ctrl = c.read(fundAuditControllerProvider(_args).notifier);
    ctrl.setCount(Denomination.p20, 3);
    await ctrl.pickPhotoAndOcr();

    final state = c.read(fundAuditControllerProvider(_args));
    expect(state.counts[Denomination.p20], 3);
    expect(state.ocrPrefilled, isEmpty);
    expect(state.ocrRunning, isFalse);
    expect(state.ocrAttemptedNoMatch, isTrue);
  });

  test('save builds a FundAudit with snapshotted names + signed variance',
      () async {
    final repo = repoWithOutstanding([
      FundRequest(
        id: 'r1',
        companyId: 'c1',
        fundId: 'f1',
        createdByUid: 'u9',
        beneficiaryName: 'b',
        amount: Money.fromCentavos(30000),
        purpose: 'p',
        proofImageUrl: '',
        status: FundRequest.fromMap('x', {'status': 'released'}).status,
      ),
    ]);
    when(() => repo.create(any())).thenAnswer((_) async => const Ok('audit1'));

    final c = _container(repo: repo);
    addTearDown(c.dispose);
    // Keep the autoDispose providers the controller reads in save() alive across
    // the awaits below; without a listener companiesProvider would re-subscribe
    // (and read empty) by the time save() snapshots the company name.
    c.listen(companiesProvider, (_, _) {});
    c.listen(currentUserProvider, (_, _) {});
    final sub = c.listen(fundAuditControllerProvider(_args), (_, _) {});
    addTearDown(sub.close);
    await c.read(companyFundsProvider('c1').future);
    await c.read(currentUserProvider.future);
    await c.read(companiesProvider.future);

    final ctrl = c.read(fundAuditControllerProvider(_args).notifier);
    ctrl.setCount(Denomination.p100, 5); // 50000 physical
    await Future<void>.delayed(Duration.zero); // settle outstanding load
    ctrl.setNote('end of month');

    final res = await ctrl.save();
    expect(res.valueOrNull, 'audit1');

    final captured =
        verify(() => repo.create(captureAny())).captured.single as FundAudit;
    expect(captured.fundName, 'Petty Cash');
    expect(captured.companyName, 'Acme');
    expect(captured.custodianUid, 'u1');
    expect(captured.custodianName, 'Cathy Custodian');
    expect(captured.note, 'end of month');
    expect(captured.physicalCash.centavos, 50000);
    expect(captured.outstanding.centavos, 30000);
    // 100000 - 50000 - 30000 = 20000 shortage (signed positive)
    expect(captured.varianceCentavos, 20000);
    expect(captured.denominations, hasLength(13));
  });
}
