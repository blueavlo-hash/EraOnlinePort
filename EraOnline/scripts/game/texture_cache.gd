class_name TextureCache
extends RefCounted
## Era Online - TextureCache
## Loads and caches bitmap textures from assets/graphics/.
## Replaces VB6's DirectDraw SurfaceDB() array.
##
## Color key: black pixels (R=0, G=0, B=0) are converted to transparent,
## matching VB6's DDCKEY_SRCBLT color key set to 0.

const GRAPHICS_PATH := "res://assets/graphics/"
const EXTENSIONS    := ["png", "PNG", "bmp", "BMP", "jpg", "JPG", "jpeg", "JPEG"]

var _cache: Dictionary = {}  # file_num (int) -> Texture2D


## Get or load a texture by Grh file number (grh1.bmp, grh2.bmp, ...).
func get_texture(file_num: int) -> Texture2D:
	if file_num in _cache:
		return _cache[file_num]
	var tex := _load(file_num)
	if tex:
		_cache[file_num] = tex
	return tex


## Evict a texture from cache to free VRAM.
func evict(file_num: int) -> void:
	_cache.erase(file_num)


## Clear entire cache.
func clear() -> void:
	_cache.clear()


## Preload a range of file numbers (call before loading a map).
func preload_range(from_num: int, to_num: int) -> void:
	for i in range(from_num, to_num + 1):
		get_texture(i)


func _load(file_num: int) -> Texture2D:
	# Build all name variants to handle mixed-case filenames in the asset folder:
	#   grh1.png  Grh1.png  GRH1.PNG  etc.
	var prefixes := ["grh", "Grh", "GRH"]
	for ext in EXTENSIONS:
		for prefix in prefixes:
			var file_name := "%s%d.%s" % [prefix, file_num, ext]
			var external_path := _get_external_graphics_path(file_name)
			if not external_path.is_empty():
				var img := Image.load_from_file(external_path)
				if img != null and not img.is_empty():
					_apply_color_key(img)
					return ImageTexture.create_from_image(img)
			# res:// path — case must match what the Godot project imported
			var res_path := GRAPHICS_PATH + file_name
			var tex := load(res_path) as Texture2D
			if tex != null:
				var img := tex.get_image()
				if img != null and not img.is_empty():
					_apply_color_key(img)
					return ImageTexture.create_from_image(img)
				return tex
	push_warning("[TextureCache] Not found: grh%d (tried all prefix/ext variants)" % file_num)
	return null


func _get_external_graphics_path(file_name: String) -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()
	if exe_dir.is_empty():
		return ""
	var candidates := [
		exe_dir.path_join("assets").path_join("graphics").path_join(file_name),
		exe_dir.path_join("graphics").path_join(file_name),
	]
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


## Convert pure-black pixels to fully transparent.
## Matches VB6's DDCKEY_SRCBLT color key set to 0.
## Since all BMPs were converted to lossless PNG, only exact black (0,0,0)
## needs masking — no JPEG artifact buffer required.
## Processes raw bytes for performance - runs once per texture on first load.
func _apply_color_key(img: Image) -> void:
	img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()  # Returns a copy (PackedByteArray value type)
	var i := 0
	while i < data.size():
		# RGBA8 layout: [R, G, B, A, R, G, B, A, ...]
		if data[i] == 0 and data[i + 1] == 0 and data[i + 2] == 0:
			data[i + 3] = 0  # Make transparent
		i += 4
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
