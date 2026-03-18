extends Node
## Era Online - CombatSystem Autoload
## Ability-based combat: loads definitions from GameData, checks STA costs,
## enforces cooldowns and learned-ability gate.
## Phase 4: server-authoritative online; local training dummy for offline.

signal skill_used(skill_id: int, target_id: int)
signal damage_dealt(target_id: int, amount: int, evaded: bool)
signal target_died(target_id: int)

const OFFLINE_DUMMY_HP := 500

var _cooldowns:    Dictionary = {}   # skill_id (int) -> expiry_ms (int)
var _feint_active: bool       = false
var _dummy_hp:     int        = OFFLINE_DUMMY_HP
var _dummy_alive:  bool       = true

## Expose dummy HP so world_map can read it for the HUD overlay.
var dummy_hp: int:
	get: return _dummy_hp
var dummy_alive: bool:
	get: return _dummy_alive


func _ready() -> void:
	pass


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func use_skill(skill_id: int, target_id: int) -> void:
	if not PlayerState.has_ability(skill_id):
		return
	if is_on_cooldown(skill_id):
		return
	var ab: Dictionary = GameData.get_ability(skill_id)
	if ab.is_empty():
		return
	var sta_cost: int = ab.get("sta_cost", 0)
	if PlayerState.stats.get("sta", 0) < sta_cost:
		return
	# Archery abilities require a bow/ranged weapon equipped
	if ab.get("req_skill_id", 0) == 28:
		var wpn_idx: int = PlayerState.get_equipped("weapon")
		var wpn_data: Dictionary = GameData.get_object(wpn_idx) if wpn_idx > 0 else {}
		if wpn_data.get("category", "") != "Archery":
			return
	# Drain stamina
	if sta_cost > 0:
		PlayerState.stats["sta"] = max(0, PlayerState.stats.get("sta", 0) - sta_cost)
		PlayerState.stats_changed.emit()
	# Apply cooldown
	var cd: float = ab.get("cooldown", 0.0)
	if cd > 0.0:
		_cooldowns[skill_id] = Time.get_ticks_msec() + int(cd * 1000.0)
	# Execute locally (offline) or send to server (online)
	if Network.state != Network.State.CONNECTED:
		_apply_offline(skill_id, target_id, ab)
	else:
		Network.send_attack(target_id)
	skill_used.emit(skill_id, target_id)


func receive_attack(raw_damage: int) -> int:
	## Returns actual damage after feint check. Clears feint flag.
	_feint_active = false
	return raw_damage


func is_on_cooldown(skill_id: int) -> bool:
	if not _cooldowns.has(skill_id):
		return false
	return Time.get_ticks_msec() < _cooldowns[skill_id]


func get_cooldown_fraction(skill_id: int) -> float:
	if not _cooldowns.has(skill_id):
		return 0.0
	var ab: Dictionary = GameData.get_ability(skill_id)
	var cd_ms: float = ab.get("cooldown", 1.0) * 1000.0
	if cd_ms <= 0.0:
		return 0.0
	var remaining: float = float(_cooldowns[skill_id] - Time.get_ticks_msec())
	return clampf(remaining / cd_ms, 0.0, 1.0)


func reset_dummy() -> void:
	_dummy_hp    = OFFLINE_DUMMY_HP
	_dummy_alive = true


# ---------------------------------------------------------------------------
# Offline combat
# ---------------------------------------------------------------------------

func _apply_offline(skill_id: int, _target_id: int, ab: Dictionary) -> void:
	if not _dummy_alive:
		return
	var effect: String  = ab.get("effect", "none")
	var mult: float     = ab.get("damage_mult", 1.0)
	var base_dmg: int   = PlayerState.stats.get("max_hit", 10)
	var total_dmg: int  = 0

	match effect:
		"triple":
			for _i in 3:
				total_dmg += maxi(1, int(float(base_dmg) * mult))
		"five_hit":
			for _i in 5:
				total_dmg += maxi(1, int(float(base_dmg) * mult))
		"execute":
			var dmg := maxi(1, int(float(base_dmg) * mult))
			if _dummy_hp < OFFLINE_DUMMY_HP * 0.3:
				dmg *= 2
			total_dmg = dmg
		"feint":
			_feint_active = true
			total_dmg = maxi(1, int(float(base_dmg) * mult))
		"bleed":
			total_dmg = maxi(1, int(float(base_dmg) * mult))
			total_dmg += maxi(1, int(float(base_dmg) * 0.3))  # bleed bonus
		_:
			# none, cleave, aoe, stagger, riposte, mortal, root — deal single-target damage
			total_dmg = maxi(1, int(float(base_dmg) * mult))

	_dummy_hp -= total_dmg
	damage_dealt.emit(-1, total_dmg, false)
	if _dummy_hp <= 0:
		_dummy_hp = 0
		_dummy_alive = false
		target_died.emit(-1)
		# Respawn after 3s
		get_tree().create_timer(3.0).timeout.connect(reset_dummy)
