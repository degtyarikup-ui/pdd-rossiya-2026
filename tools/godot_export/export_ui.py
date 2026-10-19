#!/usr/bin/env python3
"""Interface strings of the Godot game from the app's ARB files (ru/en/kk):
python3 tools/godot_export/export_ui.py  ->  game_godot/data/ui.json
Placeholders {name} are kept; Godot substitutes them in ui.gd."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
KEYS = [
    "close", "gameLeaderboard", "gameRatingLoading", "gameRatingReload", "gameRatingPendingRun", "gameRatingEmpty", "gameRatingUnavailable", "gameRatingStaleAt", "gameRatingYou",
    "gameResultNoRuns", "gameResultRanking", "gameRunMistakesButton", "gameDistance", "gameMistakesReview",
    'reportQuestionTooltip', 'reportQuestionBody', 'reportQuestionHint',
    'reportSend', 'reportSending', 'reportSent', 'reportFailed', 'cancel',
    'gameDebugPerfMemoryFootprint', 'gameDebugTier', 'gameDebugPerfObjects', 'gameDebugPerfRetained',
    'gameDebugMenuTitle', 'gameDebugRewardCar', 'gameDebugRewardPaint', 'gameDebugRewardQueue', 'gameDebugRewardHint',
    'gameDebugPerfShow', 'gameDebugPerfHide',
    'gameCarSedan', 'gamePaintBlue',
    'gameExitToMenu', 'soundEffects', 'gameSeconds', 'gameContinue', 'gameFinishRide', 'gameCorrect', 'gameMistake', 'gameTimeUp', 'gameCorrectAnswer',
    'gameGarage', 'gameLobbyRecord', 'gameLobbyColour', 'gameLobbyNewRun', 'gameRunsTitle',
    'gameAchievementsTitle', 'gameAchievementsHint', 'gameAchievementProgress',
    'gameUnlockCar', 'gameUnlockPaint',
    'gameAchievementsComplete', 'gamePaintAllCars',
    'gameAchievementCount', 'gameSoundOn', 'gameSoundOff',
    'gameVoiceOn', 'gameVoiceOff', 'gameVoiceUnavailable',
    'gameSpeedUnit', 'gameMeters', 'gameKilometers', 'gameViolations', 'gamePause', 'gamePauseSound', 'gamePauseVoice', 'gameRunProgress',
    'gameSpeedLimitLabel', 'gameOncoming', 'gameOneWayAgainst', 'gameRoadworksHit', 'gameCollision',
    'gameOffroad', 'gamePriorityViolation', 'gameSpeeding', 'gameOvertakingProhibited', 'gamePedestrianYield',
    'gameRailwayViolation', 'gameStopViolation', 'gameRedLightViolation', 'gameWrongManeuver', 'gameIllegalManeuver', 'gameLeft',
    'gameRight', 'gameGas', 'gameOver', 'gameCorrectAnswers', 'gameAnswersOf', 'gameNoViolations', 'gameScore', 'gameBrake', 'gameGasHint', 'gameResolving', 'gameExit', 'gameLobbyContinue',
    'ticket', 'gameTipGas', 'gameTipSteer', 'gameTipTurn', 'gameTipNext', 'gameTipDone',
    'gameTrafficControllerTitle', 'gameTrafficSignalQuestion', 'gameTrafficHintButton',
    'gameTrafficHintArmUp', 'gameTrafficHintForwardFront', 'gameTrafficHintForwardRight',
    'gameTrafficHintForwardLeft', 'gameTrafficHintWall', 'gameTrafficHintSide',
    'gameTrafficHintBack', 'gameTrafficHintTramLeft', 'gameTrafficHintTramStraight',
    'gameActionStraight', 'gameActionRight', 'gameActionLeft', 'gameActionUTurn', 'gameActionStand',
    'gameRestart', 'gameBestScoreLabel', 'gameNewRecord', 'gameSolvedLabel', 'gameAccuracyLabel', 'gameComboLabel',
    'gameBestScore', 'gameCurrentCombo', 'gameSecondsLeft', 'gameOverTitle',
    'gameCrossroadsPriorityTitle', 'gameCrossroadsPromptWhoGoesFirst', 'gameCrossroadsPromptWhoGoesNext',
    'gameCrossroadsStepOf', 'gameCrossroadsCollision', 'gameCrossroadsShouldGo',
    'gameCrossroadsHowTo', 'gameCrossroadsTapHint', 'gameCrossroadsResetCamera',
    'gameCrossroadsNextCrossroad', 'gameCrossroadsRepeatCrossroad',
    'continueButton', 'crossroadsReasonRedLight', 'crossroadsArticleRedLight',
    'gameCrossroadsCatAll', 'gameCrossroadsCatSigns', 'gameCrossroadsCatTrafficLights', 'gameCrossroadsCatHard',
    'gameCrossroadsCatRoundabout', 'gameCrossroadsCatRegulator', 'gameCrossroadsCatBicycles',
    'gameCrossroadsModeBlitz', 'gameCrossroadsModePractice', 'gameCrossroadsTopics', 'gameCrossroadsSolved', 'gameCrossroadsTryAgain',
    'gameCrossroadsModeArcade', 'gameCrossroadsModeTraining',
    'crossroadsHardSituationBadge', 'crossroadsHardBonusBadge', 'crossroadsTimeBonus10s', 'crossroadsPedestrian',
    'crossroadsReasonPedestrianViolation', 'crossroadsArticlePedestrian', 'crossroadsReasonEarlyExit', 'crossroadsArticleEarlyExit', 'gameCrossroadsCrash', 'gameAnswerWrong',
    'gameCrossroadsSolvedCount', 'gameCrossroadsExplanationTitle', 'gameCrossroadsCompleteTitle',
    'gameParkingTouch', 'gameParkingParked', 'gameParkingFindSpot', 'gameParkingBusStop', 'gameParkingNoStopping', 'gameParkingJunction',
]
out = {}
for lang in ('ru', 'en', 'kk'):
    arb = json.loads((ROOT / f'lib/l10n/app_{lang}.arb').read_text(encoding='utf-8'))
    out[lang] = {k: arb[k] for k in KEYS if k in arb}
    missing = [k for k in KEYS if k not in arb]
    if missing:
        print(lang, 'missing', missing)
(ROOT / 'game_godot/data/ui.json').write_text(json.dumps(out, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
print('ok', {k: len(v) for k, v in out.items()})
