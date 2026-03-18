extends Node
## Era Online - AudioManager Autoload
## Handles sound effects and music.
## Replaces VB6 MCI32 (MIDI music) and DirectSound (WAV effects).

const SOUNDS_PATH := "res://assets/sounds/"
const MUSIC_PATH  := "res://assets/music/"
const MAX_SFX_PLAYERS := 8

## Sound index constants — numbers match VB6 Declarations.bas SOUND_* exactly.
## Each value is also the sndN.wav file number (e.g. COINS = 8 → snd8.wav).
enum Sound {
	BUMP          =  1,   # Wall bump / blocked movement
	SWING         =  2,   # Melee weapon swing (miss / attack start)
	WARP          =  3,   # Tile warp / teleport
	PAPER         =  4,   # Paper / parchment (crafting blueprints, item drop)
	DRAGFISH      =  5,   # Fishing drag
	FISHINGPOLE   =  6,   # Fishing cast
	BURN          =  7,   # Fire / burning
	COINS         =  8,   # Gold / coins (pickup, buy, sell)
	NIGHTLOOP     =  9,   # Night ambient loop
	FIREBALL      = 10,   # Fireball spell
	FIREBALL2     = 11,   # Fireball variant
	FOLDCLOTHING  = 12,   # Tailoring / folding cloth
	FORRESTLOOP   = 13,   # Forest ambient loop
	FORRESTLOOP2  = 14,   # Forest ambient loop 2
	FEMALESCREAM  = 15,   # Female player hit
	SPELLEFFECT1  = 16,   # Generic spell effect 1
	HAMMERING     = 17,   # Hammering (blacksmithing)
	LIGHTNING     = 18,   # Lightning spell
	LOCKPICKING   = 19,   # Lockpicking skill
	MALEHURT      = 20,   # Male player hit
	MALEHURT2     = 21,   # Male player hit 2 / NPC death grunt
	MEDOWLOOP     = 22,   # Meadow ambient loop
	METALHIT      = 23,   # Metal-on-metal hit (armoured melee)
	SPELLEFFECT2  = 24,   # Generic spell effect 2
	SAILING       = 25,   # Sailing / water
	SAW           = 26,   # Carpentry saw
	SHORE         = 27,   # Shoreline ambient
	SMITHING      = 28,   # Blacksmith anvil strike
	SPELLEFFECT3  = 29,   # Generic spell effect 3
	SPELLEFFECT4  = 30,   # Generic spell effect 4
	SPELLEFFECT5  = 31,   # Generic spell effect 5
	STREAM        = 32,   # Stream / water ambient
	SWAMPLOOP     = 33,   # Swamp ambient loop
	SWORDSWING    = 34,   # Sword swing (crafting, skill use)
	SWORDHIT      = 35,   # Sword hit variant 1
	SWORDHIT2     = 36,   # Sword hit variant 2 (hit connects)
	WINDLOOP      = 37,   # Wind ambient loop
	STORMLOOP     = 38,   # Storm ambient loop
	SPELLEFFECT6  = 39,   # Generic spell effect 6
	CHOPPING      = 40,   # Lumberjacking chop
	MEDIVAL       = 41,   # Medieval ambience
	CHORUS        = 42,   # Level-up / triumph chime
	THUNDER       = 43,   # Thunder (weather)
	BIRDS         = 44,   # Birdsong 1
	SNAKE         = 45,   # Snake NPC sound
	SHEEP         = 46,   # Sheep NPC sound
	MONSTER1      = 47,   # Generic monster sound 1
	MONSTER2      = 48,   # Generic monster sound 2
	COW           = 49,   # Cow NPC sound
	COW2          = 50,   # Cow NPC sound 2
	GREMLIN       = 51,   # Gremlin NPC sound
	HORSE         = 52,   # Horse NPC sound
	WOLF          = 53,   # Wolf NPC sound
	CHICKEN       = 54,   # Chicken NPC sound
	ROAR          = 55,   # Roar (large monster)
	LAUGHEVIL     = 56,   # Evil laugh
	HEART         = 57,   # Heartbeat (low HP warning, heal spells)
	CLICK         = 58,   # UI click / button
	BIRDS2        = 59,   # Birdsong 2
	BEE           = 60,   # Bee / insect ambient
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

## Footstep cycling — rotates through snd3.ogg variants (snd3b/c/d/e) so steps
## don't sound identical every time.  Only used when play_sound(Sound.WARP) is
## called from the footstep path in world_map.gd.
const FOOTSTEP_VARIANTS := ["snd3", "snd3b", "snd3c", "snd3d"]
var _footstep_idx: int = 0

func play_footstep() -> void:
	var stream := _load_stream(SOUNDS_PATH + "short-muffled-footstep-sound.mp3")
	if stream == null:
		return
	var player := _get_free_player()
	if player == null:
		return
	player.stream = stream
	player.volume_db = linear_to_db(sfx_volume)
	player.play()

func _get_sfx_stream(sound_num: int) -> AudioStream:
	return _get_sfx_stream_by_key("snd%d" % sound_num)

func _get_sfx_stream_by_key(key: String) -> AudioStream:
	if key in _sfx_cache:
		return _sfx_cache[key]
	# Prefer OGG (higher quality replacements), fall back to WAV (originals).
	var stream := _load_stream(SOUNDS_PATH + key + ".ogg")
	if stream == null:
		stream = _load_stream(SOUNDS_PATH + key + ".wav")
	if stream:
		_sfx_cache[key] = stream
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
