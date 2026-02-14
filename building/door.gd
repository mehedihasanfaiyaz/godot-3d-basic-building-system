extends StaticBody3D

@export var open_angle: float = 90.0
@export var transition_speed: float = 0.3

var is_open: bool = false
var is_moving: bool = false
var initial_rotation: Vector3
@onready var pivot: Node3D = $Pivot

func _ready():
	initial_rotation = pivot.rotation
	add_to_group("interactable")

func interact(_player):
	if is_moving: return
	
	is_open = !is_open
	is_moving = true
	
	var target_rot = initial_rotation
	if is_open:
		target_rot.y += deg_to_rad(open_angle)
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(pivot, "rotation", target_rot, transition_speed)
	tween.finished.connect(_on_tween_finished)
	
	# Play a sound here if we had one
	# print("Door is now ", "Open" if is_open else "Closed")

func _on_tween_finished():
	is_moving = false

func get_interact_text() -> String:
	return "Close" if is_open else "Open"
