extends Node
## Era Online - AudioManager Autoload
## Handles sound effects and music.
## Replaces VB6 MCI32 (MIDI music) and DirectSound (WAV effects).

const SOUNDS_PATH := "res://assets/sounds/"
const MUSIC_PATH  := "res://assets/music/"
const MAX_SFX_PLAYERS := 8

## Sound index constants matching original snd1.wav naming
enum Sound {
	BUMP          = 1,
	SWING         = 2,
	WARP          = 3,
	DRAGFISH      = 4,
	FISHINGPOLE   = 5,
	BURN          = 6,
	COINS         = 7,
	FIREBALL      = 8,
	FOLDCLOTHING  = 9,
	METALHIT      = 10,
	SWORDSWING    = 11,
	SWORDHIT      = 12,
	SNAKE         = 20,
	SHEEP         = 21,
	COW           = 22,
	HORSE         = 23,
	WOLF          = 24,
	CHICKEN       = 25,
	GREMLIN       = 26,
	ROAR          = 27,
	BIRDS         = 28,
	BEE           = 29,
}

var sfx_volume: float  = 1.0
var music_volume: float = 0.7

var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _sfx_cache: Dictionary = {}
var _current_music_num: int = 0

func _ready() -> void:
	for i in MAX_SFX_PLAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	add_child(_music_player)

func play_sound(sound_num: int) -> void:
	if sound_num <= 0:
		return
	var stream := _get_sfx_stream(sound_num)
	if stream == null:
		return
	var player := _get_free_player()
	if player == null:
		return
	player.stream = stream
	player.volume_db = linear_to_db(sfx_volume)
	player.play()

func play_music(music_num: int, loop: bool = true) -> void:
	if music_num == _current_music_num and _music_player.playing:
		return
	_current_music_num = music_num
	var stream := _load_stream(MUSIC_PATH + "Mus%d.ogg" % music_num)
	if stream == null:
		push_warning("[AudioManager] Music not found: Mus%d.ogg" % music_num)
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = loop
	_music_player.stream = stream
	_music_player.volume_db = linear_to_db(music_volume)
	_music_player.play()

func stop_music() -> void:
	_music_player.stop()
	_current_music_num = 0

func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)

func set_music_volume(vol: float) -> void:
	music_volume = clampf(vol, 0.0, 1.0)
	_music_player.volume_db = linear_to_db(music_volume)

func _get_sfx_stream(sound_num: int) -> AudioStream:
	if sound_num in _sfx_cache:
		return _sfx_cache[sound_num]
	var stream := _load_stream(SOUNDS_PATH + "snd%d.wav" % sound_num)
	if stream:
		_sfx_cache[sound_num] = stream
	return stream

func _get_free_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	return _sfx_players[0]  # Steal oldest if all busy

func _load_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as AudioStream
