#!/usr/bin/env python3
"""Offline preparation evidence, never a browser-data migration tool.

Only synthetic data is generated. No browser profile, credentials or production
API is opened. --flutter additionally exercises the actual ProgressDataSource
against an in-memory SharedPreferences store. A browser test must separately
seed local-storage.fixture.json into a disposable, network-isolated staging
profile and compare it after app startup and reload.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DS = "lib/data/sources/progress_data_source.dart"
GAME = "lib/presentation/screens/game/godot_game.dart"

# The values here are cloud snapshot paths, not an assertion that cloud sync is
# a complete backup. app_settings is exported but not applied by cloud import.
CLOUD_FIELDS = {
    "question_progress_ab": "questionProgressAb",
    "question_progress_cd": "questionProgressCd",
    "ticket_progress_ab": "ticketProgressAb",
    "ticket_progress_cd": "ticketProgressCd",
    "favorite_states_ab": "favoriteStatesAb",
    "favorite_states_cd": "favoriteStatesCd",
    "favorites_ab": "favoritesAb",
    "favorites_cd": "favoritesCd",
    "exam_results_ab": "examResultsAb",
    "exam_results_cd": "examResultsCd",
    "progress_reset_at": "resetAt",
    "traffic_controller_progress": "miniGames.regulator",
    "sign_swiper_progress": "miniGames.signs",
    "crossroads_priority_progress": "miniGames.crossroads",
    "streak_current": "streak.current",
    "streak_longest": "streak.longest",
    "streak_last_active": "streak.lastActiveDate",
    "streak_start_date": "streak.startDate",
    "streak_active_days": "streak.activeDays",
    "game_best_score": "game.bestScore",
    "game_garage_cars": "game.garageCars",
    "game_garage_correct": "game.garageCorrect",
    "game_garage_unlocks": "game.garageUnlocks",
    "game_vehicle": "game.vehicle",
    "game_vehicle_paint": "game.vehiclePaint",
    "app_settings": "settings (export only; current import does not apply)",
}

LOCAL_FIELDS = {
    "unfinished_session": DS,
    "progress_mutation_clock": DS,
    "streak_celebration_pending": DS,
    "game_run_pending": GAME,
    "game_seen_models": GAME,
    "game_tips_seen": GAME,
    "game_seen": GAME,
    "godot_city_sound": GAME,
    "godot_city_voice": GAME,
    "godot_city_perf": GAME,
    "game_runs": "lib/data/services/game_runs_service.dart",
    "game_runs_since": "lib/data/services/game_runs_service.dart",
    "godot_city_question_history_v1": "lib/data/services/game_question_history_service.dart",
    "review_prompt_completions_v1": "lib/data/services/review_prompt_service.dart",
    "review_prompt_requested": "lib/data/services/review_prompt_service.dart",
    "feed_sound_enabled": "lib/presentation/screens/feed/feed_screen.dart",
    "feed_swipe_hint_count": "lib/presentation/screens/feed/feed_screen.dart",
    "notification_prompt_shown": "lib/presentation/screens/home/home_screen.dart",
    "home_exam_concept_index": "lib/presentation/widgets/exam_hero_card.dart",
}


def encoded(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def inventory(root: Path = ROOT) -> dict:
    """Fail when known preference keys no longer occur in the audited source."""
    for key, source in {**dict.fromkeys(CLOUD_FIELDS, DS), **LOCAL_FIELDS}.items():
        if repr(key) not in (root / source).read_text():
            raise ValueError(f"Inventory needs review: {key} absent from {source}")
    return {
        "schema": 1,
        "scope": "Source audit and synthetic offline verification; no real user backup",
        "sharedPreferencesWeb": {"storage": "localStorage", "prefix": "flutter.", "encoding": "JSON value; JSON strings are encoded twice"},
        "cloudSnapshotFields": CLOUD_FIELDS,
        "localOnlyFields": LOCAL_FIELDS,
        "dynamicLocalOnlyPatterns": {
            "game_best_rank:<userId>": "Per-account cached rank; server remains authoritative",
            "notifications_ru_*": "Notification consent/config/seen and topic schema",
            "support_inbox_seen_<clientId>": "Support read receipt",
            "support_chat_msgs_<clientId>": "Support conversation cache; may contain personal data",
            "support_client_id": "Preserve support identity separately, do not publish",
            "default_avatar_<userId>": "Avatar setting",
            "apple_name_<sub> / apple_email_<sub>": "Account metadata, personal data",
            "premium_*": "Cached entitlements and local quota counters; server revalidation required",
            "pending_sbp_order / pending_sbp_at / pending_sbp_owner / pending_sbp_keep_until_resolved": "Pending payment, preserve owner; never confirms purchase",
            "iap_pending_owners_v1": "Store purchase owner recovery; preserve separately",
            "install_id / install_reported / acquisition_v1": "Installation and source identity",
            "usage_events_v1 / error_events_v1": "Queued diagnostics; may contain personal data",
            "ai_explanation_v2_*": "AI answer cache; not authoritative progress",
            "app_update_ru_ready / app_update_ru_available": "Update prompt timestamp",
        },
        "otherStores": [
            {"storage": "flutter_secure_storage", "key": "pdd_server_session", "action": "Do not import into staging; reauthenticate on final origin"},
            {"storage": "sessionStorage", "key": "pdd_web_oauth_pending", "action": "Transient OAuth state; never copy between origins"},
            {"storage": "Godot user:// (web persistent filesystem / IndexedDB)", "keys": ["city-question-history-v1.json", "city-question-history-v1.json.tmp", "crossroads_practice.json"], "action": "Inventory actual web filesystem separately before full migration; not covered by Flutter prefs"},
            {"storage": "CacheStorage/service workers", "action": "Rebuild on new origin; never treat cache as progress backup"},
        ],
        "limits": [
            "Does not read or back up a real user's browser data.",
            "Does not implement a cross-origin import, conflict resolution, OAuth or payments.",
            "Synthetic map roundtrip is not a production migration or browser persistence proof.",
            "Real guest data is accessible only on its original origin until explicitly exported.",
            "Inventory is a preparation checklist; unknown keys/stores must be reviewed before migration.",
        ],
    }


def synthetic_preferences(session_kind: str = "training") -> dict[str, object]:
    if session_kind not in ("training", "exam"):
        raise ValueError("Unknown synthetic unfinished session kind")
    stamp = 1792339200000  # fixed fixture; not a wall-clock dependent test
    when = "2026-10-18T16:00:00.000Z"
    prefs: dict[str, object] = {}
    for category in ("ab", "cd"):
        prefs[f"question_progress_{category}"] = encoded({
            "q_1_1": {"isCorrect": True, "selectedAnswerIndex": 1, "attemptsCount": 3, "correctAttempts": 2, "wrongAttempts": 1, "answeredAt": when},
            "q_1_2": {"isCorrect": False, "selectedAnswerIndex": 0, "attemptsCount": 1, "correctAttempts": 0, "wrongAttempts": 1, "answeredAt": when},
        })
        prefs[f"ticket_progress_{category}"] = encoded({"1": {"correctAnswers": 17, "totalAnswered": 20, "answeredAt": when}})
        prefs[f"favorites_{category}"] = encoded(["q_1_1"])
        prefs[f"favorite_states_{category}"] = encoded({"q_1_1": {"present": True, "updatedAt": stamp}, "q_1_2": {"present": False, "updatedAt": stamp + 1}})
        prefs[f"exam_results_{category}"] = encoded([encoded({"ticketNumber": 1, "correctAnswers": 20, "wrongAnswers": 0, "passed": True, "completedAt": when})])
    prefs.update({
        "progress_reset_at": 0, "progress_mutation_clock": stamp + 1,
        "streak_current": 3, "streak_longest": 9, "streak_last_active": "2026-10-18",
        "streak_start_date": "2026-10-16", "streak_active_days": ["2026-10-16", "2026-10-17", "2026-10-18"],
        "streak_celebration_pending": True,
        "app_settings": encoded({"languageCode": "ru", "ticketCategory": "ab", "themeMode": "light", "vehicleOnboardingCompleted": True, "hapticsEnabled": False, "soundEffectsEnabled": False, "confirmAnswerEnabled": True, "voiceEnabled": False, "notificationsEnabled": False, "pushMessagesEnabled": False}),
        "traffic_controller_progress": encoded({"bestScore": 123, "maxCombo": 4, "totalSolved": 12, "trainingCount": 3}),
        "sign_swiper_progress": encoded({"bestScore": 234, "maxCombo": 5, "totalSwiped": 23, "trainingCount": 4}),
        "crossroads_priority_progress": encoded({"bestScore": 345, "maxCombo": 6, "totalSolved": 34, "trainingCount": 5}),
        "game_best_score": 456, "game_garage_cars": encoded([{"id": "sedan", "paint": "blue"}]),
        "game_garage_correct": 7, "game_garage_unlocks": 0, "game_vehicle": "sedan", "game_vehicle_paint": "blue",
        "game_runs": 1, "game_runs_since": stamp,
        "game_run_pending": encoded({"run_id": "synthetic-migration-run", "answered": 4, "correct": 3, "score": 111, "streak": 2, "violations": 1, "distance_m": 321, "mistakes": ["ticket_1_2"]}),
        "godot_city_question_history_v1": encoded({"version": 1, "sequence": 4, "last_shown": {"ticket_1_2": 4}, "show_counts": {"ticket_1_2": 2}}),
        "game_seen_models": ["sedan"], "game_tips_seen": True, "game_seen": True,
        "godot_city_sound": False, "godot_city_voice": False, "godot_city_perf": False,
        "review_prompt_completions_v1": 2, "review_prompt_requested": True,
        "feed_sound_enabled": False, "feed_swipe_hint_count": 3,
        "notification_prompt_shown": True, "home_exam_concept_index": 2,
        "unfinished_session": encoded({"title": "Тест сохранения — синтетические данные", "questionIds": ["q_1_1", "q_1_2"], "index": 1, "category": "ab", "savedAt": stamp}),
    })
    if session_kind == "exam":
        prefs["unfinished_session"] = encoded({
            "kind": "exam", "questionIds": ["q_1_1", "q_1_2"], "answers": [1, None],
            "index": 1, "remainingSeconds": 217, "totalSeconds": 1500,
            "additionalPhase": True, "additionalQuestionsCount": 5,
            "initialWrongCount": 1, "examGroups": [0, 1], "category": "ab", "savedAt": stamp,
        })
    return prefs


def web_storage(prefs: dict[str, object]) -> dict[str, str]:
    return {f"flutter.{key}": encoded(value) for key, value in prefs.items()}


def restore_web_storage(storage: dict[str, str]) -> dict[str, object]:
    return {key.removeprefix("flutter."): json.loads(value) for key, value in storage.items() if key.startswith("flutter.")}


def flutter_test(fixture: Path) -> str:
    # Fixture path is embedded as JSON to avoid code/shell interpolation.
    path_literal = json.dumps(str(fixture))
    return r'''import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = Map<String, Object>.from(jsonDecode(File(FIXTURE_PATH).readAsStringSync()) as Map);
  test('raw prefs restore and reload preserve synthetic A/B C/D and local-only data', () async {
    SharedPreferences.setMockInitialValues(fixture);
    final before = ProgressDataSource();
    await before.init();
    final prefs = await SharedPreferences.getInstance();
    final serialized = jsonEncode({for (final k in prefs.getKeys()) k: prefs.get(k)});
    SharedPreferences.setMockInitialValues(Map<String, Object>.from(jsonDecode(serialized) as Map));
    final after = ProgressDataSource();
    await after.init();
    final reloaded = await SharedPreferences.getInstance();
    for (final key in fixture.keys) {
      expect(reloaded.get(key), fixture[key], reason: key);
    }
    for (final category in TicketCategory.values) {
      expect(await after.isQuestionAnswered('q_1_1', category), true);
      expect((await after.getQuestionProgress('q_1_2', category))!['isCorrect'], false);
      expect(await after.isFavorite('q_1_1', category), true);
      expect(await after.isFavorite('q_1_2', category), false);
      expect(await after.getTicketCorrectAnswers(1, category), 17);
      expect((await after.getExamResults(category)).single['passed'], true);
    }
    expect(after.loadUnfinishedSession(TicketCategory.ab)!['index'], 1);
    expect(after.getTrafficControllerProgress().bestScore, 123);
    expect(after.getSignSwiperProgress().bestScore, 234);
    expect(after.getCrossroadsPriorityProgress().bestScore, 345);
    expect(after.getGameBestScore(), 456);
  });
  test('ordinary cloud snapshot is explicitly insufficient for complete browser backup', () async {
    SharedPreferences.setMockInitialValues(fixture);
    GameGarageService.instance.resetForTest();
    final before = ProgressDataSource();
    await before.init();
    final snapshot = before.exportProgressSnapshot();
    expect(snapshot['settings'], isNotEmpty);
    SharedPreferences.setMockInitialValues({});
    final after = ProgressDataSource();
    await after.init();
    await after.importProgressSnapshot(snapshot);
    final restored = await SharedPreferences.getInstance();
    expect(await after.isQuestionAnswered('q_1_1', TicketCategory.ab), true);
    for (final key in ['unfinished_session', 'game_run_pending', 'game_runs', 'game_runs_since', 'godot_city_question_history_v1', 'godot_city_sound', 'streak_celebration_pending', 'app_settings']) {
      expect(restored.containsKey(key), false, reason: '$key is not restored by cloud import');
    }
    final states = jsonDecode(restored.getString('favorite_states_ab')!) as Map;
    expect(states['q_1_2']['present'], false, reason: 'favorite deletion must survive');
  });
  test('raw prefs restore also preserves unfinished exam timer and additional phase', () async {
    final examFixture = Map<String, Object>.from(jsonDecode(File(FIXTURE_PATH.replaceFirst('preferences.fixture.json', 'preferences-exam.fixture.json')).readAsStringSync()) as Map);
    SharedPreferences.setMockInitialValues(Map<String, Object>.from(jsonDecode(jsonEncode(examFixture)) as Map));
    final source = ProgressDataSource();
    await source.init();
    final exam = source.loadUnfinishedSession(TicketCategory.ab)!;
    expect(exam['kind'], 'exam');
    expect(exam['remainingSeconds'], 217);
    expect(exam['additionalPhase'], true);
    expect(exam['answers'], [1, null]);
    expect(exam['additionalQuestionsCount'], 5);
  });
}
'''.replace("FIXTURE_PATH", path_literal)


def write_artifacts(output: Path, flutter: str | None = None) -> dict:
    output = output.resolve()
    if not any(output.is_relative_to(ROOT / allowed) for allowed in ("output", "scratch")):
        raise ValueError("Temporary evidence must stay in this worktree's output/ or scratch/")
    output.mkdir(parents=True, exist_ok=True)
    prefs = synthetic_preferences()
    stored = web_storage(prefs)
    restored = restore_web_storage(json.loads(encoded(stored)))
    if restored != prefs:
        raise ValueError("Synthetic raw preference roundtrip lost information")
    files = {
        "progress-storage-inventory.json": inventory(),
        "preferences.fixture.json": prefs,
        "local-storage.fixture.json": stored,
        "preferences-exam.fixture.json": synthetic_preferences("exam"),
        "local-storage-exam.fixture.json": web_storage(synthetic_preferences("exam")),
    }
    for name, value in files.items():
        (output / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    fixture = output / "preferences.fixture.json"
    test_path = output / "domain_progress_test.dart"
    test_path.write_text(flutter_test(fixture))
    report = {"syntheticOnly": True, "preferences": len(prefs), "rawMapRoundtrip": "passed", "realBrowserReload": "not_run", "flutterProgressDataSourceTests": "not_run", "files": {name: hashlib.sha256((output / name).read_bytes()).hexdigest() for name in files}}
    if flutter:
        result = subprocess.run([flutter, "test", "--no-pub", str(test_path)], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (output / "flutter-progress-test.log").write_text(result.stdout)
        report["flutterProgressDataSourceTests"] = "passed" if result.returncode == 0 else "failed"
        report["flutterExitCode"] = result.returncode
    (output / "progress-verification.json").write_text(json.dumps(report, indent=2) + "\n")
    if report["flutterProgressDataSourceTests"] == "failed":
        raise RuntimeError(f"Flutter verification failed; inspect {output / 'flutter-progress-test.log'}")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "output/domain-migration/progress")
    parser.add_argument("--flutter", help="Optional Flutter executable; run isolated actual data-source tests")
    args = parser.parse_args()
    print(json.dumps(write_artifacts(args.output, args.flutter), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
