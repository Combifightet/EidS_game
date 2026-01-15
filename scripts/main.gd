extends Control

func _ready() -> void:
	$VBoxContainer/DifficultyHSlider.value = Global.difficulty


func _on_start_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _on_character_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_editor.tscn")


func _on_quit_game_pressed() -> void:
	get_tree().quit()


func _on_difficulty_h_slider_value_changed(value: float) -> void:
	Global.difficulty = int(value) as FloorPlanGen.HouseSize
	$VBoxContainer/HBoxContainer/SelectedDifficultyLabel.text = FloorPlanGen.HouseSize.keys()[Global.difficulty].to_lower()
	$VBoxContainer/HBoxContainer/SelectedDifficultyLabel.text += " "
