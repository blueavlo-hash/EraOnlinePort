class_name RateLimiter
## Era Online - Token Bucket Rate Limiter
## One instance per ClientSession. Tracks per-message-type token buckets.
## Configured by NetProtocol.RATE_LIMITS: msg_type → [tokens_per_sec, burst].
##
## Token buckets refill lazily on consume() — no timer needed.
## Default for unknown message types: 10 tokens/sec, burst 20.

const DEFAULT_RATE  : float = 10.0
const DEFAULT_BURST : float = 20.0

## Bucket state per message type: msg_type (int) → {tokens: float, last_time: float}
var _buckets: Dictionary = {}


## Try to consume one token for the given message type.
## Returns true (allowed) or false (rate-limited, drop the packet).
func consume(msg_type: int) -> bool:
	var now    := Time.get_ticks_msec() / 1000.0
	var bucket := _get_or_create(msg_type)

	# Refill tokens based on elapsed time
	var elapsed      := now - bucket["last_time"]
	var rate: float  = bucket["rate"]
	var burst: float = bucket["burst"]
	bucket["tokens"]    = minf(burst, bucket["tokens"] + elapsed * rate)
	bucket["last_time"] = now

	if bucket["tokens"] < 1.0:
		return false  # Rate limited

	bucket["tokens"] -= 1.0
	return true


## Reset all buckets (call on disconnect/reconnect).
func reset() -> void:
	_buckets.clear()


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _get_or_create(msg_type: int) -> Dictionary:
	if msg_type in _buckets:
		return _buckets[msg_type]

	var rate  := DEFAULT_RATE
	var burst := DEFAULT_BURST

	var limits = NetProtocol.RATE_LIMITS.get(msg_type, null)
	if limits != null:
		rate  = float(limits[0])
		burst = float(limits[1])

	var bucket := {
		"tokens":    burst,       # Start full
		"last_time": Time.get_ticks_msec() / 1000.0,
		"rate":      rate,
		"burst":     burst,
	}
	_buckets[msg_type] = bucket
	return bucket
