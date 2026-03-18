class_name TextureCache
extends RefCounted
## Era Online - TextureCache
## Loads and caches bitmap textures from assets/graphics/.
## Replaces VB6's DirectDraw SurfaceDB() array.
##
## Color key: black pixels (R=0, G=0, B=0) are converted to transparent,
## matching VB6's DDCKEY_SRCBLT color key set to 0.

const GRAPHICS_PATH := "res://assets/graphics/"
const EXTENSIONS    := ["bmp", "BMP", "jpg", "JPG", "jpeg", "JPEG", "png", "PNG"]

var _cache: Dictionary = {}  # file_num (int) -> ImageTexture


## Get or load a texture by Grh file number (grh1.bmp, grh2.bmp, ...).
func get_texture(file_num: int) -> ImageTexture:
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


func _load(file_num: int) -> ImageTexture:
	for ext in EXTENSIONS:
		var path := GRAPHICS_PATH + "grh%d.%s" % [file_num, ext]
		if ResourceLoader.exists(path):
			var img := Image.load_from_file(path)
			if img:
				_apply_color_key(img)
				var tex := ImageTexture.create_from_image(img)
				return tex
	push_warning("[TextureCache] Not found: grh%d (tried bmp/jpg/png)" % file_num)
	return null


## Convert black (or near-black) pixels to fully transparent.
## Matches VB6's DDCKEY_SRCBLT color key set to 0.
## Threshold of 8 handles JPEG compression artifacts around pure-black edges.
## Processes raw bytes for performance - runs once per texture on first load.
func _apply_color_key(img: Image) -> void:
	img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()  # Returns a copy (PackedByteArray value type)
	var i := 0
	while i < data.size():
		# RGBA8 layout: [R, G, B, A, R, G, B, A, ...]
		if data[i] <= 8 and data[i + 1] <= 8 and data[i + 2] <= 8:
			data[i + 3] = 0  # Make transparent
		i += 4
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
