## Web audio fetches begin from a scene's _ready(), while its parent is locked.
## A local HTTP fixture exercises real HTTPRequest attachment, bytes and cleanup.
extends SceneTree

var failures := 0
var checks := 0
var server := TCPServer.new()
var peers: Array[StreamPeerTCP] = []
var headers := {}
var responses := {}
var outcomes := {}
var port := 0
var startup: Startup


class Startup extends Node:
	var base := ""
	var outcomes: Dictionary

	func _ready() -> void:
		for kind in GameSound.EFFECT_VOLUMES:
			var path := "res://answer_audio/%s.wav" % kind
			outcomes[path] = []
			PackFiles._waiting[path] = [func(ok: bool): outcomes[path].append(ok)]
			PackFiles._request_url(path, base + kind + ".wav")


func _initialize() -> void:
	for candidate in range(18950, 19050):
		if server.listen(candidate, "127.0.0.1") == OK:
			port = candidate
			break
	for kind in GameSound.EFFECT_VOLUMES:
		responses["/%s.wav" % kind] = FileAccess.get_file_as_bytes(
			ProjectSettings.globalize_path("res://../assets/audio/%s.wav" % kind))
	if port != 0:
		startup = Startup.new()
		startup.base = "http://127.0.0.1:%d/" % port
		startup.outcomes = outcomes
		# Attach before the root's first _ready traversal, matching web boot.
		root.add_child(startup)
	run.call_deferred()


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)


func poll_server() -> void:
	while server.is_connection_available():
		var peer := server.take_connection()
		peers.append(peer)
		headers[peer] = ""
	for peer in peers.duplicate():
		peer.poll()
		var count: int = peer.get_available_bytes()
		if count == 0:
			continue
		headers[peer] += peer.get_utf8_string(count)
		if not str(headers[peer]).contains("\r\n\r\n"):
			continue
		var path: String = str(headers[peer]).split("\r\n")[0].split(" ")[1]
		var found := responses.has(path)
		var body: PackedByteArray = responses.get(path, PackedByteArray())
		var status := "200 OK" if found else "404 Not Found"
		var response := ("HTTP/1.1 %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, body.size()]).to_utf8_buffer()
		response.append_array(body)
		peer.put_data(response)
		peer.disconnect_from_host()
		peers.erase(peer)
		headers.erase(peer)


func wait_for_requests(paths: Array) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		poll_server()
		var done := true
		for path in paths:
			if outcomes[path].is_empty(): done = false
		if done: break
		await process_frame
	# Completion queues the request for deletion after callbacks return.
	await process_frame
	await process_frame


func run() -> void:
	check(port != 0, "Local HTTP fixture starts")
	if port == 0:
		quit(1)
		return
	for path in outcomes:
		check(outcomes[path].is_empty(), "Startup fetch waits until scene attachment finishes: " + path)
	await wait_for_requests(outcomes.keys())
	for path in outcomes:
		check(outcomes[path] == [true], "Startup audio completes once: " + path)
		check(not PackFiles._waiting.has(path), "Startup audio releases its waiting callbacks: " + path)
		var expected: PackedByteArray = responses["/" + str(path).get_file()]
		check(not expected.is_empty() and PackFiles._bytes.get(path) == expected, "Startup audio keeps the exact shared WAV: " + path)
	var missing := "res://answer_audio/missing.wav"
	outcomes[missing] = []
	PackFiles._waiting[missing] = [func(ok: bool): outcomes[missing].append(ok)]
	PackFiles._request_url(missing, startup.base + "missing.wav")
	await wait_for_requests([missing])
	check(outcomes[missing] == [true] and PackFiles._absent.has(missing), "A missing optional file completes once and is marked absent")
	check(not PackFiles._waiting.has(missing), "A missing optional file releases its waiting callbacks")
	var requests_left := 0
	for child in root.get_children():
		if child is HTTPRequest: requests_left += 1
	check(requests_left == 0, "Completed startup and missing-file requests are freed")
	PackFiles.forget("res://answer_audio/")
	startup.queue_free()
	server.stop()
	await process_frame
	print("Web startup audio: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
