import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/notifier_api.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local progress remains the first write. The account's latest pending snapshot
/// is persisted before upload and is acknowledged only by a valid server reply.
/// This is a coalescing snapshot outbox, not a queue of replayed answer actions.
class ProgressSyncService with WidgetsBindingObserver {
  ProgressSyncService._internal()
    : _testAuth = null,
      _now = DateTime.now,
      _jitter = Random().nextDouble,
      _retryBase = const Duration(seconds: 2),
      _retryCap = const Duration(minutes: 5);

  @visibleForTesting
  ProgressSyncService.forTesting({
    required AuthService auth,
    DateTime Function()? now,
    double Function()? jitter,
    Duration retryBase = const Duration(seconds: 2),
    Duration retryCap = const Duration(minutes: 5),
  }) : _testAuth = auth,
       _now = now ?? DateTime.now,
       _jitter = jitter ?? Random().nextDouble,
       _retryBase = retryBase,
       _retryCap = retryCap;

  static final ProgressSyncService instance = ProgressSyncService._internal();
  static const _prefix = 'progress_sync_outbox_v1:';
  final AuthService? _testAuth;
  final DateTime Function() _now;
  final double Function() _jitter;
  final Duration _retryBase, _retryCap;
  AuthService get _auth => _testAuth ?? AuthService.instance;
  final _outboxes = <String, _ProgressOutbox>{};
  Future<void> _storageTail = Future<void>.value();
  ProgressDataSource? _dataSource;
  Timer? _timer;
  DateTime? _timerAt;
  _ProgressAttempt? _inFlight;
  Future<void>? _restoration;
  int? _restoringGeneration;
  int? _restoredGeneration;
  int _generation = 0;
  String? _observedAccount;
  int? _observedAuthRevision;
  bool _attached = false, _disposed = false, _foreground = true;

  void init(ProgressDataSource dataSource) {
    cancel();
    _disposed = false;
    _dataSource = dataSource;
    if (!_attached) {
      _auth.addListener(_authChanged);
      WidgetsBinding.instance.addObserver(this);
      _attached = true;
    }
    _observedAccount = _auth.currentUser?.id;
    _observedAuthRevision = _auth.accountRevision;
    unawaited(_resume());
  }

  /// Capture immediately, even while an older upload is still in flight. Only
  /// transmission is debounced; a later reply cannot acknowledge this revision.
  void scheduleSync({Duration delay = const Duration(seconds: 3)}) {
    final context = _context();
    if (context == null) return;
    final snapshot = _snapshot(context.source);
    unawaited(() async {
      try {
        final restored = _restoredGeneration == context.generation;
        await _restore(context);
        if (!_current(context)) return;
        await _capture(
          context,
          restored ? snapshot : _snapshot(context.source),
        );
        if (!_current(context)) return;
        final outbox = _outboxes[context.id]!;
        final wait = _wait(outbox, delay);
        _arm(context, wait, replace: outbox.failures == 0);
      } catch (error) {
        _deferred(error);
        _arm(context, _retryBase);
      }
    }());
  }

  /// Invalidate pending timers and replies; the durable outbox stays attached to
  /// its original account and is resumed when that account has a session again.
  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _timerAt = null;
    _inFlight = null;
    _restoration = null;
    _restoringGeneration = null;
    _restoredGeneration = null;
  }

  void dispose() {
    cancel();
    _disposed = true;
    _dataSource = null;
    if (_attached) {
      _auth.removeListener(_authChanged);
      WidgetsBinding.instance.removeObserver(this);
      _attached = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      unawaited(_resume());
    } else {
      _timer?.cancel();
      _timer = null;
      _timerAt = null;
    }
  }

  void _authChanged() {
    if (_observedAccount == _auth.currentUser?.id &&
        _observedAuthRevision == _auth.accountRevision) {
      return;
    }
    cancel();
    _observedAccount = _auth.currentUser?.id;
    _observedAuthRevision = _auth.accountRevision;
    final context = _context();
    if (context != null) {
      unawaited(() async {
        try {
          await _stored(() async {
            final outbox = await _load(context.id);
            if (!_current(context) || !outbox.blocked) return;
            outbox.blocked = false;
            outbox.blockedSessionHash = null;
            outbox.failures = 0;
            outbox.nextAttemptAt = 0;
            await _persist(context.id, outbox);
          });
          if (_current(context)) await syncWithServer();
        } catch (error) {
          _deferred(error);
        }
      }());
    }
  }

  _ProgressContext? _context() {
    final user = _auth.currentUser, source = _dataSource;
    if (_disposed ||
        user == null ||
        source == null ||
        !_auth.hasServerSession ||
        !BackendConfig.hasNotifier) {
      return null;
    }
    return _ProgressContext(
      user.id,
      _auth.accountRevision,
      _generation,
      source,
      Map<String, String>.from(_auth.serverHeaders),
    );
  }

  bool _current(_ProgressContext context) =>
      !_disposed &&
      context.generation == _generation &&
      context.authRevision == _auth.accountRevision &&
      context.id == _auth.currentUser?.id &&
      _auth.hasServerSession &&
      identical(context.source, _dataSource);

  Future<T> _stored<T>(Future<T> Function() work) {
    final result = _storageTail.then((_) => work());
    _storageTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<_ProgressOutbox> _load(String id) async {
    if (_outboxes[id] case final existing?) return existing;
    final prefs = await SharedPreferences.getInstance();
    _ProgressOutbox outbox;
    try {
      final raw = prefs.getString(_prefix + Uri.encodeComponent(id));
      outbox = raw == null ? _ProgressOutbox() : _ProgressOutbox.decode(raw);
    } catch (_) {
      // The normal local progress remains available if only this metadata is
      // damaged. An explicit/startup sync captures it again before sending.
      outbox = _ProgressOutbox();
    }
    return _outboxes[id] = outbox;
  }

  Future<void> _persist(String id, _ProgressOutbox outbox) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      _prefix + Uri.encodeComponent(id),
      outbox.encode(),
    )) {
      throw StateError('progress outbox persistence failed');
    }
  }

  Future<void> _capture(
    _ProgressContext context,
    String snapshot, {
    bool force = false,
  }) => _stored(() async {
    final outbox = await _load(context.id);
    if (outbox.blocked && outbox.blockedSessionHash != _sessionHash(context)) {
      // A restored, newly issued session may exist before this service attaches
      // its listener. Store only its digest, never the credential itself.
      outbox.blocked = false;
      outbox.blockedSessionHash = null;
      outbox.failures = 0;
      outbox.nextAttemptAt = 0;
    }
    if ((outbox.pending && outbox.snapshot != snapshot) ||
        (!outbox.pending &&
            (force || outbox.acknowledgedHash != _hash(snapshot)))) {
      outbox.revision++;
      outbox.snapshot = snapshot;
    }
    await _persist(context.id, outbox);
  });

  Future<void> _restore(_ProgressContext context) {
    if (_restoredGeneration == context.generation) return Future<void>.value();
    if (_restoringGeneration == context.generation && _restoration != null) {
      return _restoration!;
    }
    _restoringGeneration = context.generation;
    return _restoration = () async {
      try {
        final snapshot = await _stored(() async {
          final outbox = await _load(context.id);
          return outbox.pending ? outbox.snapshot : null;
        });
        if (!_current(context)) return;
        if (snapshot != null) {
          await context.source.importProgressSnapshot(
            Map<String, dynamic>.from(jsonDecode(snapshot) as Map),
            stillCurrent: () => _current(context),
          );
        }
        if (_current(context)) _restoredGeneration = context.generation;
      } finally {
        if (_restoringGeneration == context.generation) {
          _restoration = null;
          _restoringGeneration = null;
        }
      }
    }();
  }

  Future<void> _resume() async {
    final context = _context();
    if (context == null || !_foreground) return;
    try {
      await _restore(context);
      final pending = await _stored(
        () async => (await _load(context.id)).pending,
      );
      if (pending && _current(context)) await _pump(context);
    } catch (error) {
      _deferred(error);
      _arm(context, _retryBase);
    }
  }

  /// One awaited attempt. Transient failures remain durable and schedule bounded
  /// retries; callers never wait through a whole offline/backoff period.
  Future<void> syncWithServer() async {
    final context = _context();
    if (context == null) return;
    try {
      await _restore(context);
      if (!_current(context)) return;
      await _capture(context, _snapshot(context.source), force: true);
      await _pump(context);
    } catch (error) {
      _deferred(error);
      _arm(context, _retryBase);
    }
  }

  Future<void> _pump(_ProgressContext context) async {
    if (!_current(context) || !_foreground || _inFlight != null) return;
    await _restore(context);
    if (!_current(context) || !_foreground || _inFlight != null) return;
    // Include local changes made immediately before a timer/foreground event.
    // Persistence must finish before any network request can be created.
    await _capture(context, _snapshot(context.source));
    if (!_current(context) || !_foreground || _inFlight != null) return;
    final outbox = _outboxes[context.id]!;
    if (!outbox.pending || outbox.blocked) return;
    final wait = _wait(outbox, Duration.zero);
    if (wait > Duration.zero) {
      _arm(context, wait);
      return;
    }
    final attempt = _ProgressAttempt(
      context,
      outbox.revision,
      outbox.snapshot!,
    );
    _inFlight = attempt;
    _timer?.cancel();
    _timer = null;
    _timerAt = null;
    try {
      String appVersion = '', platform = '';
      try {
        final info = await PackageInfo.fromPlatform().timeout(
          const Duration(seconds: 2),
        );
        appVersion = '${info.version}+${info.buildNumber}';
        platform = kIsWeb ? 'web' : Platform.operatingSystem;
      } catch (_) {}
      if (!_current(context)) return;
      final response = await NotifierApi.post(
        '/api/user/progress/sync',
        idempotent: true,
        headers: context.headers,
        body: jsonEncode({
          'userId': context.id,
          'progress': jsonDecode(attempt.snapshot),
          if (appVersion.isNotEmpty) 'appVersion': appVersion,
          if (platform.isNotEmpty) 'platform': platform,
        }),
      );
      if (!_current(context)) return;
      if (response.statusCode != 200) {
        final retryable =
            response.statusCode >= 500 ||
            [408, 425, 429].contains(response.statusCode);
        await _failure(
          attempt,
          retryable: retryable,
          retryAfter: _retryAfter(response.headers['retry-after']),
        );
        return;
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['ok'] != true || body['progress'] is! Map) {
        await _failure(attempt, retryable: true);
        return;
      }
      await context.source.importProgressSnapshot(
        Map<String, dynamic>.from(body['progress'] as Map),
        stillCurrent: () => _current(context),
      );
      if (!_current(context)) return;
      final importedSnapshot = _snapshot(context.source);
      await _stored(() async {
        if (!_current(context)) return;
        final latest = _ProgressOutbox.decode(
          (await _load(context.id)).encode(),
        );
        if (!_current(context)) return;
        latest.acknowledged = max(latest.acknowledged, attempt.revision);
        // Refresh the queued snapshot after merge, but never acknowledge a
        // newer local revision with an older request's response.
        latest.snapshot = latest.pending
            ? _snapshot(context.source)
            : importedSnapshot;
        if (!latest.pending) {
          latest.acknowledgedHash = _hash(latest.snapshot!);
          latest.snapshot = null;
        }
        latest.failures = 0;
        latest.nextAttemptAt = 0;
        latest.blocked = false;
        await _persist(context.id, latest);
        _outboxes[context.id] = latest;
      });
    } catch (error) {
      if (_current(context)) {
        _deferred(error);
        await _failure(
          attempt,
          // Local import/prefs failures must not become an authorization block.
          // Only an explicit non-retryable HTTP response pauses that session.
          retryable: true,
        );
      }
    } finally {
      if (identical(_inFlight, attempt)) {
        _inFlight = null;
        if (_current(context)) {
          final latest = _outboxes[context.id]!;
          if (latest.pending && !latest.blocked) {
            _arm(context, _wait(latest, Duration.zero));
          }
        }
      }
    }
  }

  Future<void> _failure(
    _ProgressAttempt attempt, {
    required bool retryable,
    Duration? retryAfter,
  }) => _stored(() async {
    if (!_current(attempt.context)) return;
    final outbox = _ProgressOutbox.decode(
      (await _load(attempt.context.id)).encode(),
    );
    outbox.failures = min(outbox.failures + 1, 30);
    outbox.blocked = !retryable;
    outbox.blockedSessionHash = retryable
        ? null
        : _sessionHash(attempt.context);
    final base = min(
      _retryCap.inMilliseconds,
      _retryBase.inMilliseconds * (1 << min(outbox.failures - 1, 20)),
    );
    final milliseconds = min(
      _retryCap.inMilliseconds,
      max(_retryBase.inMilliseconds, (base * (0.75 + _jitter() * 0.5)).round()),
    );
    final delay = Duration(milliseconds: milliseconds);
    outbox.nextAttemptAt = _now()
        .add(retryAfter != null && retryAfter > delay ? retryAfter : delay)
        .millisecondsSinceEpoch;
    await _persist(attempt.context.id, outbox);
    _outboxes[attempt.context.id] = outbox;
  });

  Duration _wait(_ProgressOutbox outbox, Duration minimum) {
    final remaining = Duration(
      milliseconds: outbox.nextAttemptAt - _now().millisecondsSinceEpoch,
    );
    return remaining > minimum ? remaining : minimum;
  }

  void _arm(_ProgressContext context, Duration delay, {bool replace = false}) {
    if (!_current(context) || !_foreground) return;
    final at = _now().add(delay);
    if (!replace && _timerAt != null && !_timerAt!.isAfter(at)) return;
    _timer?.cancel();
    _timerAt = at;
    _timer = Timer(delay, () {
      _timer = null;
      _timerAt = null;
      if (_current(context)) {
        unawaited(
          _pump(context).catchError((Object error) {
            _deferred(error);
            _arm(context, _retryBase);
          }),
        );
      }
    });
  }

  Duration? _retryAfter(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    try {
      final delay = HttpDate.parse(value).difference(_now());
      return delay > Duration.zero ? delay : Duration.zero;
    } catch (_) {
      return null;
    }
  }

  /// A pull never acknowledges or discards the local upload queue.
  Future<void> pullFromServer() async {
    final context = _context();
    if (context == null) return;
    try {
      await _restore(context);
      if (!_current(context)) return;
      final response = await NotifierApi.get(
        '/api/user/progress',
        query: {'userId': context.id},
        headers: context.headers,
      );
      if (response.statusCode != 200 || !_current(context)) return;
      final body = jsonDecode(response.body);
      if (body is Map && body['ok'] == true && body['progress'] is Map) {
        await context.source.importProgressSnapshot(
          Map<String, dynamic>.from(body['progress'] as Map),
          stillCurrent: () => _current(context),
        );
      }
    } catch (error) {
      _deferred(error);
    }
  }

  static String _snapshot(ProgressDataSource source) {
    Object? canonical(Object? value, {bool root = false}) {
      if (value is Map) {
        final keys =
            value.keys
                .whereType<String>()
                .where(
                  (key) => !root || !['updatedAt', 'lastSeenAt'].contains(key),
                )
                .toList()
              ..sort();
        return {for (final key in keys) key: canonical(value[key])};
      }
      return value is List
          ? value.map((item) => canonical(item)).toList()
          : value;
    }

    return jsonEncode(canonical(source.exportProgressSnapshot(), root: true));
  }

  static void _deferred(Object error) =>
      debugPrint('Progress sync deferred (${error.runtimeType})');

  static String _hash(String snapshot) =>
      sha256.convert(utf8.encode(snapshot)).toString();

  static String _sessionHash(_ProgressContext context) =>
      _hash(context.headers['authorization'] ?? '');
}

class _ProgressContext {
  _ProgressContext(
    this.id,
    this.authRevision,
    this.generation,
    this.source,
    this.headers,
  );
  final String id;
  final int authRevision, generation;
  final ProgressDataSource source;
  final Map<String, String> headers;
}

class _ProgressAttempt {
  _ProgressAttempt(this.context, this.revision, this.snapshot);
  final _ProgressContext context;
  final int revision;
  final String snapshot;
}

class _ProgressOutbox {
  int revision = 0, acknowledged = 0, failures = 0, nextAttemptAt = 0;
  String? snapshot;
  String? acknowledgedHash;
  String? blockedSessionHash;
  bool blocked = false;
  bool get pending => snapshot != null && revision > acknowledged;
  _ProgressOutbox();
  factory _ProgressOutbox.decode(String raw) {
    final body = jsonDecode(raw) as Map;
    if (body['version'] != 1 ||
        (body['snapshot'] != null && body['snapshot'] is! Map)) {
      throw const FormatException('invalid progress outbox');
    }
    final outbox = _ProgressOutbox()
      ..revision = (body['revision'] as num).toInt()
      ..acknowledged = (body['acknowledgedRevision'] as num).toInt()
      ..failures = (body['failures'] as num?)?.toInt() ?? 0
      ..nextAttemptAt = (body['nextAttemptAt'] as num?)?.toInt() ?? 0
      ..blocked = body['blocked'] == true
      ..blockedSessionHash = body['blockedSessionHash'] as String?
      ..acknowledgedHash = body['acknowledgedHash'] as String?
      ..snapshot = body['snapshot'] == null
          ? null
          : jsonEncode(body['snapshot']);
    if (outbox.revision < 0 ||
        outbox.acknowledged < 0 ||
        outbox.acknowledged > outbox.revision ||
        outbox.failures < 0 ||
        (outbox.revision > outbox.acknowledged && outbox.snapshot == null)) {
      throw const FormatException('invalid progress revision');
    }
    return outbox;
  }
  String encode() => jsonEncode({
    'version': 1,
    'revision': revision,
    'acknowledgedRevision': acknowledged,
    'snapshot': snapshot == null ? null : jsonDecode(snapshot!),
    'acknowledgedHash': acknowledgedHash,
    'failures': failures,
    'nextAttemptAt': nextAttemptAt,
    'blocked': blocked,
    'blockedSessionHash': blockedSessionHash,
  });
}
