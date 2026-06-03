import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/firebase/firebase_providers.dart';
import '../data/firestore_company_repository.dart';
import '../data/firestore_fund_repository.dart';
import '../domain/company.dart';
import '../domain/company_repository.dart';
import '../domain/fund.dart';
import '../domain/fund_repository.dart';

final companyRepositoryProvider = Provider<CompanyRepository>(
    (ref) => FirestoreCompanyRepository(ref.watch(firestoreProvider)));

final fundRepositoryProvider = Provider<FundRepository>(
    (ref) => FirestoreFundRepository(ref.watch(firestoreProvider)));

final companiesProvider = StreamProvider<List<Company>>(
    (ref) => ref.watch(companyRepositoryProvider).watchAll());

/// Funds owned by a single company.
final companyFundsProvider = StreamProvider.family<List<Fund>, String>(
  (ref, companyId) => ref.watch(fundRepositoryProvider).watchByCompany(companyId),
);
