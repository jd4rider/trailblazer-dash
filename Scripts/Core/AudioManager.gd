extends Node
## Music, ambience and sound effects.
##
## Six moods, each exported as four layers (base, bass, arp, lead). The arp and
## lead fade in with running speed, so the mix tightens as the trail gets
## faster without restarting the loop.

const SFX_DIR := "res://Assets/Audio/SFX/"
const MUSIC_DIR := "res://Assets/Audio/Music/"
const AMB_DIR := "res://Assets/Audio/Ambience/"
const SILENT_DB := -60.0

var music_volume := 0.7
var sfx_volume := 0.85

var _sfx_cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _music: Dictionary = {}
var _mood := ""
var _intensity := 0.35
var _amb_a: AudioStreamPlayer
var _amb_b: AudioStreamPlayer
var _amb_active: AudioStreamPlayer
var _amb_base: AudioStreamPlayer
var _amb_name := ""
var _kicked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(10):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)
	for layer in ["base", "bass", "arp", "lead"]:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		player.volume_db = SILENT_DB
		add_child(player)
		_music[layer] = player
	_amb_a = AudioStreamPlayer.new()
	_amb_b = AudioStreamPlayer.new()
	for player in [_amb_a, _amb_b]:
		player.bus = "Master"
		player.volume_db = SILENT_DB
		add_child(player)
	_amb_active = _amb_a
	# A quiet always-on air bed underneath the regional ambience, so a level is
	# never silent if its region bed is subtle.
	_amb_base = AudioStreamPlayer.new()
	_amb_base.bus = "Master"
	_amb_base.volume_db = SILENT_DB
	add_child(_amb_base)
	var wind := _looped(AMB_DIR + "wind.wav")
	if wind != null:
		_amb_base.stream = wind
		_amb_base.volume_db = linear_to_db(maxf(0.02, music_volume)) - 21.0
		_amb_base.play()


## Browsers hold WebAudio suspended until a real gesture, which silences every
## player started before the first tap. Called from the run once the player has
## pressed start.
func kick() -> void:
	if _kicked:
		return
	_kicked = true
	for player in _music.values():
		var layer := player as AudioStreamPlayer
		if layer.stream != null:
			layer.play()
	for player in [_amb_active, _amb_base]:
		if player != null and player.stream != null:
			player.play()


func apply_settings(settings: Dictionary) -> void:
	music_volume = clampf(float(settings.get("music", 0.7)), 0.0, 1.0)
	sfx_volume = clampf(float(settings.get("sfx", 0.85)), 0.0, 1.0)
	_apply_music_levels()
	if _amb_base != null and _amb_base.stream != null:
		_amb_base.volume_db = linear_to_db(maxf(0.02, music_volume)) - 21.0


func _stream(path: String) -> AudioStream:
	if _sfx_cache.has(path):
		return _sfx_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	_sfx_cache[path] = stream
	return stream


func _looped(path: String) -> AudioStream:
	var stream := _stream(path)
	if stream is AudioStreamWAV:
		var copy := stream.duplicate() as AudioStreamWAV
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
		copy.loop_begin = 0
		var bytes := 2 if copy.format == AudioStreamWAV.FORMAT_16_BITS else 1
		var channels := 2 if copy.stereo else 1
		copy.loop_end = int(copy.data.size() / (bytes * channels))
		return copy
	return stream


func play_sfx(name: String, pitch := 1.0, volume_db := 0.0) -> void:
	if sfx_volume <= 0.001:
		return
	var stream := _stream(SFX_DIR + name + ".wav")
	if stream == null:
		return
	var target: AudioStreamPlayer = null
	for player in _players:
		if not player.playing:
			target = player
			break
	if target == null:
		target = _players[0]
	target.stream = stream
	target.pitch_scale = clampf(pitch, 0.5, 2.0)
	target.volume_db = volume_db + linear_to_db(maxf(0.05, sfx_volume))
	target.play()


func ui_click() -> void:
	play_sfx("ui_click", randf_range(0.96, 1.05), -6.0)


func ui_back() -> void:
	play_sfx("ui_back", randf_range(0.94, 1.02), -6.0)


func step(surface: String) -> void:
	var known := ["grass", "stone", "sand", "snow", "metal", "wood", "mud"]
	var family := surface if surface in known else "grass"
	play_sfx("step_%s_%d" % [family, randi() % 3], randf_range(0.93, 1.07), -11.0)


func play_music(mood: String) -> void:
	if mood == _mood and _music["base"].playing:
		return
	_mood = mood
	for layer in _music.keys():
		var player: AudioStreamPlayer = _music[layer]
		player.stream = _looped(MUSIC_DIR + mood + "_" + layer + ".wav")
		player.play()
	_apply_music_levels()


func set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	_apply_music_levels()


func _apply_music_levels() -> void:
	if _music.is_empty():
		return
	var music_gain := linear_to_db(maxf(0.02, music_volume))
	(_music["base"] as AudioStreamPlayer).volume_db = music_gain - 8.0
	(_music["bass"] as AudioStreamPlayer).volume_db = music_gain - 6.0
	(_music["arp"] as AudioStreamPlayer).volume_db = music_gain - lerpf(26.0, 8.0, _intensity)
	(_music["lead"] as AudioStreamPlayer).volume_db = music_gain - lerpf(34.0, 12.0, _intensity)


func stop_music() -> void:
	_mood = ""
	for player in _music.values():
		(player as AudioStreamPlayer).stop()


func play_ambience(name: String) -> void:
	if name == _amb_name:
		return
	_amb_name = name
	var incoming: AudioStreamPlayer = _amb_b if _amb_active == _amb_a else _amb_a
	var outgoing := _amb_active
	var stream := _looped(AMB_DIR + name + ".wav")
	if stream == null:
		return
	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()
	_amb_active = incoming
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(incoming, "volume_db", linear_to_db(maxf(0.02, music_volume)) - 8.0, 1.6)
	tween.tween_property(outgoing, "volume_db", SILENT_DB, 1.6)
	tween.chain().tween_callback(func() -> void: outgoing.stop())


func stop_ambience() -> void:
	_amb_name = ""
	for player in [_amb_a, _amb_b]:
		var tween := create_tween()
		tween.tween_property(player, "volume_db", SILENT_DB, 0.8)
		tween.tween_callback(player.stop)
