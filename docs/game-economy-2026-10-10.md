# Game rewards, 2026-10-10

Goal: visible progress for beginners, modest incentives for mastery, bounded
weekly accumulation shared by all games.

| Game | Correct answer / completed situation | Streak cap |
| --- | --- | --- |
| Sign swiper | 12 points | 16 |
| Traffic controller | 24 points | 32 |
| Living city | 40 points | 50 |
| Crossroads | 40 points | 50 |

- Each successive correct answer adds 1 point in signs, 2 in the other games,
  up to the stated cap. A mistake resets the streak, not the earned score.
- Regulator hints award half the points. Wrong answers/timeouts award zero.
  Driving faults retain warnings/counters, without deductions or negative HUD.
- Mini-games allow five mistakes. Signs and regulator have a fixed 60-second
  timer: neither correctness nor mistakes alter the timer.
- City ends after 20 answered questions for every account. Crossroads arcade
  ends after 20 completed scenes or expiry/lives. Mini-game score is bounded
  to 1,500 per round. Speed itself does not multiply rewards.
- A correct answer earns ranking points immediately, even with fewer than
  five correct answers or accuracy below 75%. The old hard cutoff is removed.
- All games share 1,500 credited ranking points per Moscow calendar day,
  up to 10,500 newly earned points per ISO week. Server enforcement also
  covers old installed clients. Local learning/records remain available.
- A stable run ID and cumulative score make retries idempotent. Live city
  delta establishes the baseline when a run crosses the weekly boundary.
  Capped excess is consumed rather than banked for the next day.
- Ranking shows today's credited amount/limit and an info dialog explaining
  rewards. Existing weekly totals, records, cars and learned content are
  retained; reachable badge thresholds were adjusted without clearing progress.
- Crossroads is enabled only with GAME_DEBUG=true (the Pixel dev build).
  Its collision explanation bridge and late callbacks after game over are fixed.
- Dev Android app label is `ПДД Россия · Тест` to distinguish it from the
  installed store app. Store app name remains unchanged.

Examples: ten correct city answers mixed with ten mistakes still earn at least
400 points; one correct sign answer followed by mistakes keeps at least 12.
A perfect 20-question city run earns 970. Fast guessing cannot accumulate
unbounded weekly rewards.

Verification: full Flutter suite, analyzer, fixed-time and beginner UI tests,
reachable achievement boundaries, server daily/cumulative/concurrency/retry
regressions and real-browser crossroads progression/DTП explanation smoke.
New delivery is a dev installation to Pixel only; no store bundles are built.
