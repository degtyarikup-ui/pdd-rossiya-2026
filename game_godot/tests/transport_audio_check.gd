## Broadband hiss, duplicate refreshes, and real stream starvation regression.
extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(message)
func _initialize() -> void:
 run.call_deferred()
func run() -> void:
 var sound := GameSound.new()
 sound.enabled = false
 root.add_child(sound)
 sound.set_process(false)
 sound.enabled = true
 for i in 120: sound.vehicle("same-car", "car", 14.0)
 check(sound._vehicles.size() == 1, "refreshing one car never doubles its engine")
 var voice := GameSound.TransportVoice.new()
 voice.configure("car", 14.0)
 var energy := 0.0
 var difference := 0.0
 var previous := 0.0
 seed(42)
 for i in 22050:
  var sample := sound._engine_sample(voice, 1.0)
  if i > 4410:
   energy += sample * sample
   difference += (sample - previous) * (sample - previous)
  previous = sample
 check(energy > 1.0, "motor remains audible after filtering road noise")
 check(difference / energy < 0.02, "steady driving has no dominating broadband hiss")
 if DisplayServer.get_name() != "headless":
  sound.speed = 12.0
  for i in 4: sound.vehicle("traffic%d" % i, "car", 9.0, false, 0.5)
  sound.set_process(true)
  for frame in 20: await process_frame
  var skipped := sound._playback.get_skips()
  # A short real render stall used to exhaust the 120ms generator ring.
  OS.delay_msec(110)
  for frame in 8: await process_frame
  check(sound._playback.get_skips() == skipped, "engine survives a 110ms frame stall without crackles")
  sound.suspended = true
  await process_frame
  check(not sound._player.playing and sound._playback == null, "results suspend transport audio completely")
 sound.queue_free()
 await process_frame
 print("Transport audio: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)
