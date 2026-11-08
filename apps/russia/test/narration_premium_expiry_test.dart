import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/premium_service.dart';

class _PremiumSnapshot extends Fake implements PremiumService {
  _PremiumSnapshot(this.expiresAt);

  @override
  DateTime? expiresAt;
  bool active = true;
  int reads = 0;

  @override
  bool get isPremium {
    reads++;
    return active;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer containerFor(_PremiumSnapshot service) => ProviderContainer(
    overrides: [
      premiumServiceProvider.overrideWithValue(service),
      progressImportsProvider.overrideWith((_) => const Stream.empty()),
      authAndPremiumStreamProvider.overrideWith((_) => const Stream.empty()),
    ],
  );

  test(
    'premium controls lock at expiry without an account or network event',
    () async {
      final service = _PremiumSnapshot(
        DateTime.now().add(const Duration(milliseconds: 60)),
      );
      final container = containerFor(service);
      addTearDown(container.dispose);
      final changes = <bool>[];
      container.listen(isPremiumProvider, (_, next) => changes.add(next));
      expect(container.read(isPremiumProvider), isTrue);
      // The authoritative service will report expiry next time it is consulted;
      // no stream event or manual provider invalidation occurs.
      service.active = false;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(container.read(isPremiumProvider), isFalse);
      expect(changes, contains(false));
    },
  );

  test('disposing the container cancels the entitlement deadline', () async {
    final service = _PremiumSnapshot(
      DateTime.now().add(const Duration(milliseconds: 60)),
    );
    final container = containerFor(service);
    expect(container.read(isPremiumProvider), isTrue);
    final reads = service.reads;
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(service.reads, reads);
  });
}
