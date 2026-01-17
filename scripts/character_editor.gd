extends Control

signal color_changed(color: Color)
signal height_changed(height: float)
signal radius_changed(radius: float)

@export var color_picker_button: ColorPickerButton
@export var height_slider: HSlider
@export var height_value_label: Label
@export var radius_slider: HSlider
@export var radius_value_label: Label
@export var character_preview_mesh: MeshInstance3D

const SAVE_FILE_PATH = "user://character_data.json"
var _preview_material: StandardMaterial3D
var _is_loading: bool = false

@onready var beanie: MeshInstance3D = $MarginContainer/VBoxContainer/Stack/SubViewportContainer/SubViewport/World3D/CharacterPreviewMesh/Beanie

func _ready() -> void:
	_load_data()
	
	 # Initialize the preview material and assign it to the mesh
	if character_preview_mesh:
		_preview_material = StandardMaterial3D.new()
		character_preview_mesh.material_override = _preview_material
		_preview_material.albedo_color = color_picker_button.color


func _process(_delta: float) -> void:	
	if Input.is_action_just_pressed("back"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_color_picker_button_color_changed(new_color: Color) -> void:
	if _preview_material:
		_preview_material.albedo_color = new_color
	
	color_changed.emit(new_color)
	
	_save_data()


func _on_height_slider_value_changed(new_height: float) -> void:
	if character_preview_mesh and character_preview_mesh.mesh is CapsuleMesh:
		var capsule_mesh: CapsuleMesh = character_preview_mesh.mesh
		capsule_mesh.height = new_height
		character_preview_mesh.position = Vector3(0, new_height/2-1, 0)
		beanie.position = Vector3(0,new_height/2,0)
	
	if height_value_label:
		height_value_label.text = "%.2f" % new_height
	
	height_changed.emit(new_height)
	
	_save_data()
	
	if new_height < radius_slider.value*3:
		var new_radius: float = new_height/3
		radius_slider.value = new_radius
		if character_preview_mesh and character_preview_mesh.mesh is CapsuleMesh:
			var capsule_mesh: CapsuleMesh = character_preview_mesh.mesh
			capsule_mesh.radius = new_radius
			
			beanie.scale = Vector3.ONE * new_radius/0.5

		if radius_value_label:
			radius_value_label.text = "%.2f" % new_radius
		
		radius_changed.emit(new_radius)
		
		_save_data()


func _on_radius_slider_value_changed(new_radius: float) -> void:
	if character_preview_mesh and character_preview_mesh.mesh is CapsuleMesh:
		var capsule_mesh: CapsuleMesh = character_preview_mesh.mesh
		capsule_mesh.radius = new_radius
		
		beanie.scale = Vector3.ONE * new_radius/0.5

	if radius_value_label:
		radius_value_label.text = "%.2f" % new_radius
	
	radius_changed.emit(new_radius)
	
	if new_radius*3 > height_slider.value:
		var new_height: float = new_radius*3
		height_slider.value = new_height
		if character_preview_mesh and character_preview_mesh.mesh is CapsuleMesh:
			var capsule_mesh: CapsuleMesh = character_preview_mesh.mesh
			capsule_mesh.height = new_height
			character_preview_mesh.position = Vector3(0, new_height/2-1, 0)
			beanie.position = Vector3(0,new_height/2,0)
		
		if height_value_label:
			height_value_label.text = "%.2f" % new_height
		
		height_changed.emit(new_height)
		
		_save_data()
	
	_save_data()


func _save_data() -> void:
	if _is_loading:
		return

	var data_to_save = {
		"color": color_picker_button.color.to_html(),
		"height": height_slider.value,
		"radius": radius_slider.value
	}
	
	var json_string = JSON.stringify(data_to_save, "\t")
	
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
	else:
		push_error("Failed to open save file for writing: %s" % SAVE_FILE_PATH)


func _load_data() -> void:
	_is_loading = true
	
	if FileAccess.file_exists(SAVE_FILE_PATH):
		var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
		var file_content = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var error = json.parse(file_content)
		
		if error == OK:
			var loaded_data = json.data
			if loaded_data is Dictionary:
				height_slider.value = loaded_data.get("height", 2.0)
				radius_slider.value = loaded_data.get("radius", 0.5)
				color_picker_button.color = Color(loaded_data.get("color", "#ffffff"))
		else:
			push_error("Error parsing save file: %s" % json.get_error_message())
	
	_on_color_picker_button_color_changed(color_picker_button.color)
	_on_height_slider_value_changed(height_slider.value)
	_on_radius_slider_value_changed(radius_slider.value)
	
	_is_loading = false
