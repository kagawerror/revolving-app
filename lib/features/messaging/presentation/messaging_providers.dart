import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/messaging/onesignal_service.dart';

final oneSignalServiceProvider =
    Provider<OneSignalService>((ref) => OneSignalService());
