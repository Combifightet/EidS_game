extends Control

@onready var text: Control = $Text
@onready var camera: Camera3D = $SubViewportContainer/SubViewport/Camera3D
@onready var vignette: ColorRect = $CreditsUI/Vignette

## durations in seconds
@export var wait_duration: float = 0.4
@export var scroll_duration: float = 40
@export var blinds_duration: float = 1.5

func _process(_delta: float) -> void:	
	if Input.is_action_just_pressed("back"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _ready() -> void:
	# wait before starting to scroll
	await get_tree().create_timer(wait_duration).timeout
	
	# Animate text position from (0, 0) to (0, -1545)
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_parallel(true)
	
	tween.tween_property(text, "position:y", -1555, scroll_duration).from(0)
	tween.tween_property(camera, "position:y", -17.3, scroll_duration).from(0)
	
	# Wait until text has scrolled 95% of the way
	await get_tree().create_timer(scroll_duration * 0.9).timeout
	
	# Animate vignette from 0.125 to 0.5 to close the 'blinds'
	var vignette_tween = create_tween()
	vignette_tween.set_ease(Tween.EASE_IN)
	vignette_tween.set_trans(Tween.TRANS_QUAD)
	
	vignette_tween.tween_method(
		func(value: float): vignette.material.set_shader_parameter("bar_ratio", value),
		0.125,
		0.5,
		blinds_duration
	)
	
	# wait before returning to menu
	await get_tree().create_timer(blinds_duration+wait_duration*2).timeout
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
