extends Node3D
class_name LevelExit

@export var is_open = false:
	set(value):
		is_open = value
		_update_visuals()

@onready var glow: MeshInstance3D = $Rim/Glow
@onready var lid: MeshInstance3D = $Rim/Lid
@onready var lid_open_pos = lid.position


func _ready() -> void:
	_update_visuals()
	

func open_exit():
	is_open = true
	_update_visuals()
	
func close_exit():
	is_open = false
	_update_visuals()

func _update_visuals():
	if not is_node_ready():
		return
	
	if is_open:
		glow.show()
		lid.position = lid_open_pos
	else:
		glow.hide()
		lid.position = Vector3.ZERO


func _on_area_3d_body_entered(_body: Node3D) -> void:
	if is_open:
		AudioController.stop_walk()
		print("EXIT GAME")	
	
		get_tree().change_scene_to_file("res://scenes/game_exit.tscn")
