class_name DeathScreenUI
extends CanvasLayer

## Death overlay with screen-blur, desaturation, and a manual Respawn button.
## Flow:
##   show_death()     → fade-in animation (blur + dark tint + panel slide-in)
##   on_respawn_data_ready() → enables Respawn button (called by world_map when
##                             S_WORLD_STATE arrives from server)
##   [player clicks Respawn] → fade-out animation → emits respawn_confirmed
##   world_map receives respawn_confirmed → applies stored teleport data

signal respawn_confirmed

enum _State { HIDDEN, FADING_IN, WAITING, FADING_OUT }

const PANEL_W := 380
const PANEL_H := 260

var _state: _State = _State.HIDDEN
var _blur_rect:    ColorRect = null
var _tint_rect:    ColorRect = null
var _panel:        Panel     = null
var _killer_label: Label     = null
var _respawn_btn:  Button    = null
var _tween: Tween = null
var _respawn_data_ready: bool = false

# Pulse phase for the waiting-state red vignette oscillation
var _pulse_t: float = 0.0


func _ready() -> void:
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _build() -> void:
	# ── Blur + desaturate layer ──────────────────────────────────────────────
	_blur_rect = ColorRect.new()
	_blur_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur_rect.modulate.a = 0.0

	var shader_code := """
shader_type canvas_item;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float blur_px : hint_range(0.0, 10.0) = 0.0;
uniform float desat   : hint_range(0.0, 1.0)  = 0.0;

void fragment() {
	vec2 ps  = SCREEN_PIXEL_SIZE * blur_px;
	vec4 col = vec4(0.0);
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			col += texture(SCREEN_TEXTURE,
				SCREEN_UV + vec2(float(x), float(y)) * ps);
		}
	}
	col /= 25.0;
	float gray = dot(col.rgb, vec3(0.299, 0.587, 0.114));
	col.rgb = mix(col.rgb, vec3(gray), desat);
	COLOR = col;
}
"""
	var sh := Shader.new()
	sh.code = shader_code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_blur_rect.material = mat
	add_child(_blur_rect)

	# ── Dark red tint overlay ────────────────────────────────────────────────
	_tint_rect = ColorRect.new()
	_tint_rect.color = Color(0.18, 0.0, 0.0, 1.0)
	_tint_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tint_rect.modulate.a = 0.0
	add_child(_tint_rect)

	# ── Central death panel ──────────────────────────────────────────────────
	_panel = Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color    = Color(0.04, 0.01, 0.01, 0.97)
	ps.border_color = Color(0.72, 0.05, 0.05, 1.0)
	ps.set_border_width_all(2)
	ps.corner_radius_top_left     = 8
	ps.corner_radius_top_right    = 8
	ps.corner_radius_bottom_left  = 8
	ps.corner_radius_bottom_right = 8
	_panel.add_theme_stylebox_override("panel", ps)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left   = -PANEL_W / 2.0
	_panel.offset_right  =  PANEL_W / 2.0
	_panel.offset_top    = -PANEL_H / 2.0
	_panel.offset_bottom =  PANEL_H / 2.0
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.78, 0.78)
	add_child(_panel)

	# Title
	var title := Label.new()
	title.text = "YOU DIED"
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color(0.92, 0.08, 0.08, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.offset_top    = 26
	title.offset_bottom = 82
	title.offset_left   = 10
	title.offset_right  = -10
	_panel.add_child(title)

	# Divider
	var sep := ColorRect.new()
	sep.color    = Color(0.52, 0.04, 0.04, 0.7)
	sep.position = Vector2(30, 88)
	sep.size     = Vector2(PANEL_W - 60, 1)
	_panel.add_child(sep)

	# Killer / cause label
	_killer_label = Label.new()
	_killer_label.add_theme_font_size_override("font_size", 15)
	_killer_label.add_theme_color_override("font_color", Color(0.82, 0.58, 0.58, 1.0))
	_killer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_killer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_killer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_killer_label.offset_top    = 98
	_killer_label.offset_bottom = 158
	_killer_label.offset_left   = 24
	_killer_label.offset_right  = -24
	_panel.add_child(_killer_label)

	# Respawn button
	_respawn_btn = Button.new()
	_respawn_btn.text     = "Respawn"
	_respawn_btn.disabled = true
	_respawn_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_respawn_btn.offset_top    = -58
	_respawn_btn.offset_bottom = -16
	_respawn_btn.offset_left   = 90
	_respawn_btn.offset_right  = -90
	_respawn_btn.add_theme_font_size_override("font_size", 16)

	var _mk_btn_style := func(bg: Color, border: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color    = bg
		s.border_color = border
		s.set_border_width_all(1)
		s.corner_radius_top_left     = 4
		s.corner_radius_top_right    = 4
		s.corner_radius_bottom_left  = 4
		s.corner_radius_bottom_right = 4
		return s

	_respawn_btn.add_theme_stylebox_override("normal",
			_mk_btn_style.call(Color(0.52, 0.06, 0.06, 1.0), Color(0.80, 0.12, 0.12, 1.0)))
	_respawn_btn.add_theme_stylebox_override("hover",
			_mk_btn_style.call(Color(0.72, 0.10, 0.10, 1.0), Color(1.00, 0.22, 0.22, 1.0)))
	_respawn_btn.add_theme_stylebox_override("pressed",
			_mk_btn_style.call(Color(0.38, 0.04, 0.04, 1.0), Color(0.70, 0.10, 0.10, 1.0)))
	_respawn_btn.add_theme_stylebox_override("disabled",
			_mk_btn_style.call(Color(0.18, 0.04, 0.04, 1.0), Color(0.38, 0.07, 0.07, 1.0)))
	_respawn_btn.add_theme_color_override("font_color",          Color(1.00, 0.78, 0.78, 1.0))
	_respawn_btn.add_theme_color_override("font_hover_color",    Color(1.00, 1.00, 1.00, 1.0))
	_respawn_btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.28, 0.28, 1.0))
	_respawn_btn.pressed.connect(_on_respawn_pressed)
	_panel.add_child(_respawn_btn)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func show_death(killer_name: String) -> void:
	_killer_label.text = "Slain by %s." % killer_name if not killer_name.is_empty() \
			else "You starved to death."

	_state = _State.FADING_IN
	_respawn_data_ready = false
	_respawn_btn.disabled = true
	_pulse_t = 0.0

	# Reset positions
	_blur_rect.modulate.a = 0.0
	_tint_rect.modulate.a = 0.0
	_panel.modulate.a     = 0.0
	_panel.scale          = Vector2(0.78, 0.78)

	var mat := _blur_rect.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("blur_px", 0.0)
		mat.set_shader_parameter("desat",   0.0)

	visible = true

	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)

	# Blur fades in over 1.6s
	_tween.tween_property(_blur_rect, "modulate:a", 1.0, 1.6) \
			.set_ease(Tween.EASE_OUT)
	if mat:
		_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("blur_px", v),
				0.0, 5.0, 1.6)
		_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("desat", v),
				0.0, 0.80, 1.6)

	# Red tint fades in over 1.8s
	_tween.tween_property(_tint_rect, "modulate:a", 0.72, 1.8) \
			.set_ease(Tween.EASE_OUT)

	# Panel slides in after 0.9s delay
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.7) \
			.set_delay(0.9).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "scale", Vector2(1.0, 1.0), 0.55) \
			.set_delay(0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	_tween.chain().tween_callback(_on_fade_in_complete)


## Called by world_map when S_WORLD_STATE (respawn data) arrives from server.
func on_respawn_data_ready() -> void:
	_respawn_data_ready = true
	if _state == _State.WAITING:
		_respawn_btn.disabled = false


func is_open() -> bool:
	return _state != _State.HIDDEN


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _state != _State.WAITING:
		return
	# Gentle red pulse on tint while waiting
	_pulse_t += delta * 0.8
	_tint_rect.modulate.a = 0.65 + sin(_pulse_t) * 0.08


func _on_fade_in_complete() -> void:
	_state = _State.WAITING
	if _respawn_data_ready:
		_respawn_btn.disabled = false


func _on_respawn_pressed() -> void:
	if _state != _State.WAITING:
		return
	_state = _State.FADING_OUT
	_respawn_btn.disabled = true

	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)

	# Panel shrinks out
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.35) \
			.set_ease(Tween.EASE_IN)
	_tween.tween_property(_panel, "scale", Vector2(0.88, 0.88), 0.35) \
			.set_ease(Tween.EASE_IN)

	# Tint and blur fade out
	_tween.tween_property(_tint_rect, "modulate:a", 0.0, 0.65) \
			.set_delay(0.15).set_ease(Tween.EASE_IN)
	var mat := _blur_rect.material as ShaderMaterial
	if mat:
		_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("blur_px", v),
				5.0, 0.0, 0.65)
		_tween.tween_method(func(v: float) -> void: mat.set_shader_parameter("desat", v),
				0.80, 0.0, 0.65)
	_tween.tween_property(_blur_rect, "modulate:a", 0.0, 0.75) \
			.set_ease(Tween.EASE_IN)

	_tween.chain().tween_callback(_finish_respawn)


func _finish_respawn() -> void:
	visible = false
	_state  = _State.HIDDEN
	respawn_confirmed.emit()
