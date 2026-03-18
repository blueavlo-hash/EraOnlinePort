class_name GrhAnimator
## Era Online - GrhAnimator
## Manages the Grh animation system ported from VB6.
## Mirrors the VB6 Grh/GrhData types from Declares.bas.
##
## Each Grh entry is either:
##   static  (num_frames=1): points to one bitmap region
##   animated(num_frames>1): cycles through multiple static Grh entries

var grh_index: int   = 0  ## Which GrhData entry this animator uses
var frame_counter: int = 1  ## Current frame (1-based, matches VB6)
var speed_counter: int = 0  ## Countdown timer to next frame
var started: bool     = false  ## True if animation is playing
var play_once: bool    = false  ## If true, stop instead of looping
var play_reverse: bool = false  ## If true, count frames down instead of up

## Initialize from a GRH index.
func init(index: int) -> void:
	grh_index     = index
	frame_counter = 1
	var entry     := GameData.get_grh(index)
	if entry.is_empty():
		started = false
		return
	var num_frames: int = entry.get("num_frames", 1)
	started       = num_frames > 1
	speed_counter = entry.get("speed", 0) if started else 0

## Advance animation by one tick. Call from _process or a timer.
func tick() -> void:
	if not started or grh_index <= 0:
		return
	var entry := GameData.get_grh(grh_index)
	var num_frames: int = entry.get("num_frames", 1)
	if num_frames <= 1:
		return
	if speed_counter > 0:
		speed_counter -= 1
		return
	speed_counter = entry.get("speed", 1)
	if play_reverse:
		frame_counter -= 1
		if frame_counter < 1:
			if play_once:
				frame_counter = 1
				started = false
			else:
				frame_counter = num_frames
	else:
		frame_counter += 1
		if frame_counter > num_frames:
			if play_once:
				frame_counter = num_frames
				started = false
			else:
				frame_counter = 1

## Returns the static GrhData dict for the current frame.
func get_frame_data() -> Dictionary:
	if grh_index <= 0:
		return {}
	var entry := GameData.get_grh(grh_index)
	if entry.is_empty():
		return {}
	var num_frames: int = entry.get("num_frames", 1)
	if num_frames <= 1:
		return entry
	var frames: Array = entry.get("frames", [])
	if frames.is_empty():
		return entry
	var idx: int = clamp(frame_counter - 1, 0, frames.size() - 1)
	return GameData.get_grh(frames[idx])

## Returns the source rect within the bitmap for the current frame.
func get_source_rect() -> Rect2i:
	var d := get_frame_data()
	if d.is_empty():
		return Rect2i()
	return Rect2i(d.get("sx",0), d.get("sy",0), d.get("pixel_width",32), d.get("pixel_height",32))

## Returns the bitmap file number for the current frame.
func get_file_num() -> int:
	return get_frame_data().get("file_num", 0)

## Returns pixel size of this Grh (from static entry or first animated frame).
func get_pixel_size() -> Vector2i:
	var d := get_frame_data()
	return Vector2i(d.get("pixel_width", 32), d.get("pixel_height", 32))
