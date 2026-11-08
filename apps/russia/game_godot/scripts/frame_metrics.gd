## Diagnostic frame durations: fixed 1 ms histogram, never an unbounded sample list.
## Quantiles use nearest-rank ceil(p * frame_count), reported as the selected
## bin's upper bound (at most 1 ms above its sample). A rank above 1000 ms is
## null, with overflow_frames retaining its count; avg/worst remain exact.
extends RefCounted

const BIN_MS := 1.0
const LIMIT_MS := 1000.0
const BIN_COUNT := 1000
var bins := PackedInt32Array()
var frame_count := 0
var sum_ms := 0.0
var worst_ms := 0.0
var over_16_7 := 0
var over_33_3 := 0
var over_50 := 0
var over_100 := 0

func _init() -> void:
	bins.resize(BIN_COUNT + 1)

func reset() -> void:
	bins.fill(0)
	frame_count = 0
	sum_ms = 0.0
	worst_ms = 0.0
	over_16_7 = 0
	over_33_3 = 0
	over_50 = 0
	over_100 = 0

func sample(seconds: float) -> void:
	if not is_finite(seconds) or seconds < 0.0: return
	var ms := seconds * 1000.0
	var index := BIN_COUNT if ms > LIMIT_MS else clampi(ceili(ms / BIN_MS) - 1, 0, BIN_COUNT - 1)
	bins[index] += 1
	frame_count += 1
	sum_ms += ms
	worst_ms = maxf(worst_ms, ms)
	if ms > 16.7: over_16_7 += 1
	if ms > 33.3: over_33_3 += 1
	if ms > 50.0: over_50 += 1
	if ms > 100.0: over_100 += 1

func quantile(fraction: float) -> Variant:
	if frame_count == 0: return null
	var rank := maxi(1, ceili(clampf(fraction, 0.0, 1.0) * frame_count))
	var seen := 0
	for i in BIN_COUNT:
		seen += bins[i]
		if seen >= rank: return (i + 1) * BIN_MS
	return null

func summary(wall_seconds: float) -> Dictionary:
	return {"frame_count": frame_count, "window_seconds": sum_ms / 1000.0,
		"wall_seconds": maxf(0.0, wall_seconds),
		"frame_avg_ms": sum_ms / frame_count if frame_count > 0 else null,
		"frame_worst_ms": worst_ms if frame_count > 0 else null,
		"p50_ms": quantile(0.50), "p95_ms": quantile(0.95), "p99_ms": quantile(0.99),
		"frames_over_16_7_ms": over_16_7, "frames_over_33_3_ms": over_33_3,
		"frames_over_50_ms": over_50, "frames_over_100_ms": over_100,
		"quantile_method": "nearest_rank_histogram_upper_bound", "quantile_bin_ms": BIN_MS,
		"quantile_limit_ms": LIMIT_MS, "overflow_frames": bins[BIN_COUNT],
		"frame_time_source": "monotonic_process_interval", "frame_scope": "all_visible_diagnostic_phases"}
