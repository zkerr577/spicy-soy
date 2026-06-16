## TransitionLayer — full-screen fade overlay.
## Add to Project > Project Settings > Autoload as "Transition"
## using the transition_layer.tscn scene file (not this script directly).
extends CanvasLayer

@onready var _overlay: ColorRect = $Overlay

const DEFAULT_DURATION := 0.35


func _ready() -> void:
	# Start fully transparent; the first fade-in in GameManager.travel_to() will clear it
	_overlay.modulate.a = 0.0


## Animate to fully black. Await this before changing scene.
func fade_out(duration: float = DEFAULT_DURATION) -> void:
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 1.0, duration).set_ease(Tween.EASE_IN)
	await tw.finished


## Animate back to transparent. Await this after the new scene has loaded.
func fade_in(duration: float = DEFAULT_DURATION) -> void:
	var tw := create_tween()
	tw.tween_property(_overlay, "modulate:a", 0.0, duration).set_ease(Tween.EASE_OUT)
	await tw.finished


## Instantly cut to black without animating (for hard cuts or loading screens).
func cut_to_black() -> void:
	_overlay.modulate.a = 1.0


## Instantly cut back to clear.
func cut_to_clear() -> void:
	_overlay.modulate.a = 0.0
