import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/data/repositories/auth_repository.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Синхронизация [ProgressDataSource] с таблицей `user_progress` в Supabase.
class ProgressCloudCoordinator {
  ProgressCloudCoordinator(this._dataSource);

  final ProgressDataSource _dataSource;

  SupabaseClient? _client;
  User? _user;
  Future<void> Function()? _invalidateUi;
  int _generation = 0;

  Future<void> sync({
    required SupabaseClient? client,
    required User? user,
    required bool guest,
    required bool supabaseAvailable,
    Future<void> Function()? invalidateUi,
  }) async {
    final gen = ++_generation;
    _invalidateUi = invalidateUi;

    _dataSource.cancelCloudDebounce();
    _dataSource.configureCloudSync(enabled: false, pushNow: _push);

    final cloudActive =
        supabaseAvailable && !guest && user != null && client != null;

    if (!cloudActive) {
      _client = null;
      _user = null;
      return;
    }

    _client = client;
    _user = user;

    try {
      await _initialSync();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Progress cloud initial sync failed: $e');
        debugPrintStack(stackTrace: st);
      }
    }

    if (gen != _generation) return;

    _dataSource.configureCloudSync(enabled: true, pushNow: _push);
  }

  Future<void> _initialSync() async {
    final client = _client!;
    final user = _user!;
    final ds = _dataSource;

    final owner = ds.storedProgressOwnerId;
    if (owner != null && owner != user.id) {
      await ds.clearAllProgressForAccountSwitch();
    }

    final localMs = ds.localProgressUpdatedMs;
    final Map<String, dynamic>? row = await client
        .from('user_progress')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null) {
      _dataSource.ensureProgressTimestamp();
      await _push();
      await ds.setStoredProgressOwnerId(user.id);
      await _invalidateUi?.call();
      return;
    }

    final remoteMs = (row['updated_at_ms'] as num?)?.toInt() ?? 0;
    if (remoteMs > localMs) {
      await ds.importFromCloudRow(Map<String, dynamic>.from(row));
      await ds.setStoredProgressOwnerId(user.id);
      await _invalidateUi?.call();
    } else if (localMs > remoteMs) {
      _dataSource.ensureProgressTimestamp();
      await _push();
      await ds.setStoredProgressOwnerId(user.id);
    } else {
      await ds.setStoredProgressOwnerId(user.id);
    }
  }

  Future<void> _push() async {
    final client = _client;
    final user = _user;
    if (client == null || user == null) return;

    try {
      _dataSource.ensureProgressTimestamp();
      final payload = _dataSource.buildCloudUpsertRow(user.id);
      await client.from('user_progress').upsert(payload, onConflict: 'user_id');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Progress cloud push failed: $e');
        debugPrintStack(stackTrace: st);
      }
    }
  }
}

final progressCloudCoordinatorProvider = Provider<ProgressCloudCoordinator>((
  ref,
) {
  return ProgressCloudCoordinator(ref.watch(progressDataSourceProvider));
});

/// Стабильная подпись сессии для ref.listen (без лишних срабатываний).
final progressCloudAuthSignalProvider = Provider<String>((ref) {
  final user = ref.watch(currentUserProvider);
  final guest = ref.watch(guestModeProvider);
  final supabase = ref.watch(supabaseAvailableProvider);
  return '${user?.id ?? ""}|$guest|$supabase';
});

/// Подписывается на сессию и синхронизирует прогресс с Supabase.
class ProgressCloudHost extends ConsumerStatefulWidget {
  const ProgressCloudHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ProgressCloudHost> createState() => _ProgressCloudHostState();
}

class _ProgressCloudHostState extends ConsumerState<ProgressCloudHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_sync());
      }
    });
  }

  Future<void> _sync() async {
    if (!mounted) return;
    final supabaseOk = ref.read(supabaseAvailableProvider);
    final coordinator = ref.read(progressCloudCoordinatorProvider);
    await coordinator.sync(
      client: supabaseOk ? ref.read(supabaseClientProvider) : null,
      user: ref.read(currentUserProvider),
      guest: ref.read(guestModeProvider),
      supabaseAvailable: supabaseOk,
      invalidateUi: () async {
        ref.read(appDataRefreshProvider.notifier).state++;
        ref.invalidate(appSettingsProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String>(progressCloudAuthSignalProvider, (prev, next) {
      if (prev != next) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_sync());
          }
        });
      }
    });
    return widget.child;
  }
}
