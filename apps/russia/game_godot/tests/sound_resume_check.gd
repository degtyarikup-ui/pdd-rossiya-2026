## Game sounds come back after the ride pause and after the app returns from the background.
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
 root.add_child(sound)
 if DisplayServer.get_name() == "headless":
  sound.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
  sound._process(1.0 / 60.0)
  check(sound._playback == null, "headless stays silent through lifecycle notifications")
 else:
  sound.speed = 10.0
  for frame in 3: await process_frame
  check(sound._player.playing and sound._playback != null, "transport audio starts")
  # Ride pause: World freezes the node and pauses every stream, then restores both.
  sound.process_mode = Node.PROCESS_MODE_DISABLED
  sound._player.stream_paused = true
  sound.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
  sound.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
  # The OS drops the output while the app is in the background.
  sound._player.stop()
  sound.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
  sound.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
  for frame in 3: await process_frame
  check(sound._playback == null, "paused sound does not restart under the garage overlay")
  sound._player.stream_paused = false
  sound.process_mode = Node.PROCESS_MODE_INHERIT
  for frame in 3: await process_frame
  check(sound._player.playing and sound._playback != null and sound._playback.get_frames_available() < 22050, "transport audio restarts after background and Continue")
  # A player stopped outside a pause (lost audio session) recovers on its own.
  sound._player.stop()
  for frame in 3: await process_frame
  check(sound._player.playing and sound._playback != null, "stopped generator restarts without a notification")
  # Plain pause cycle with a live playback keeps the same generator feeding.
  sound._player.stream_paused = true
  sound.process_mode = Node.PROCESS_MODE_DISABLED
  await process_frame
  sound._player.stream_paused = false
  sound.process_mode = Node.PROCESS_MODE_INHERIT
  for frame in 3: await process_frame
  check(sound._player.playing and not sound._player.stream_paused, "pause and Continue keep transport audio playing")
 sound.queue_free()
 await process_frame
 print("Sound resume: %d checks, %d failures" % [checks, failures])
 quit(1 if failures else 0)
