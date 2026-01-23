extends CharacterBody3D
class_name Guard

@export_range(0, 255, 1) var id: int = 0 

# --- Configuration ---
@export_range(0, 180, 1, "radians_as_degrees") var vision_angle: float = deg_to_rad(60.0)
@export var view_dist: float = 4.0
@export var detection_time: float = 0.5 ## time to be caught in seconds
@export var eyes_height: float = 0.5
@export var move_duration: float = 0.4 # How fast the guard moves between tiles
@export var rotation_duration: float = 0.3 # How fast the guard rotates towards movement direction

# --- References ---
@onready var vision_area: Area3D = $VisionArea
@onready var ray_cast: RayCast3D = $RayCast3D
@onready var spot_indicator: Label3D = $SpotIndicator
@onready var vision_cone: VisionCone = $VisionArea/VisionCone
@onready var view_range: CollisionShape3D = $VisionArea/ViewRange

# --- State ---
var target_player: PlayerMovement = null
var detection_timer: float = 0.0
var is_alert: bool = false
var is_in_range: bool = false

# --- Navigation & Patrol ---
var astar_graph = AStar2D.new()
var cell_to_id: Dictionary = {}
var _grid_origin := Vector3.ZERO
var _grid_resolution: float = 1.0

var patrol_points: Array[Vector2i] = [] # The list of collectible locations
var current_patrol_index: int = 0
var current_path: PackedVector2Array = []
var is_moving: bool = false
var active_tween: Tween
var rotation_tween: Tween

func _ready() -> void:
	ray_cast.add_exception(self)
	ray_cast.enabled = false
	spot_indicator.text = ""
	
	vision_cone.id = id
	vision_cone.angle = vision_angle
	vision_cone.view_distance = view_dist
	view_range.scale = Vector3(view_dist, 1, view_dist)
	
	check_vision(0)


func set_id(new_id: int):
	id = new_id
	vision_cone.id = id

func set_vision_angle(new_angle: float):
	vision_angle = new_angle
	vision_cone.angle = vision_angle

func set_view_dist(new_dist: float):
	view_dist = new_dist
	vision_cone.view_distance = view_dist
	view_range.scale = Vector3(view_dist, 1, view_dist)


func _physics_process(delta: float) -> void:
	# 1. Vision Logic (Existing)
	if target_player:
		check_vision(delta)
	else:
		if detection_timer > 0:
			detection_timer = max(0.0, detection_timer - delta)
			update_indicator()

	# 2. Patrol Logic (New)
	# Only move if not alert and we have a path
	if not is_alert and not patrol_points.is_empty():
		_process_patrol_movement()

# --- Vision System (Existing + Fix) ---
func check_vision(delta: float) -> void:
	if is_in_range:
		var can_see = false
		var guard_eyes = global_position + Vector3(0, eyes_height, 0)
		var player_center = target_player.global_position + Vector3(0, eyes_height, 0) 
		
		var direction_to_player_2d = (player_center - guard_eyes)
		direction_to_player_2d.y = 0 
		direction_to_player_2d = direction_to_player_2d.normalized()
		
		var forward_vector_2d = -global_transform.basis.z
		forward_vector_2d.y = 0 
		forward_vector_2d = forward_vector_2d.normalized()
		
		var angle_to_player = forward_vector_2d.angle_to(direction_to_player_2d)
		if angle_to_player < vision_angle/2.0:
			ray_cast.global_position = guard_eyes
			ray_cast.target_position = ray_cast.to_local(player_center)
			ray_cast.force_raycast_update()
			
			if ray_cast.is_colliding():
				var collider = ray_cast.get_collider()
				if collider == target_player:
					can_see = true
		
		if can_see:
			detection_timer += delta
			is_alert = true
			
			# Stop moving if we see the player!
			if active_tween and active_tween.is_running():
				active_tween.kill()
			if rotation_tween and rotation_tween.is_running():
				rotation_tween.kill()
			is_moving = false
			
			if detection_timer >= detection_time:
				game_over()
			_set_cone_color(Color(1.0, 0.0, 0.0, 0.5))
		else:
			detection_timer = max(0.0, detection_timer - delta)
			is_alert = false # Resume patrol in next frame
			_set_cone_color(Color(0.0, 0.5, 1.0, 0.3))
		
		update_indicator()
	else:
		is_alert = false # Resume patrol in next frame
		_set_cone_color(Color(0.0, 0.5, 1.0, 0.3))

# --- Movement System (Adapted from PlayerMovement) ---

func setup_navigation(origin: Vector3, resolution: float, grid_data: Dictionary) -> void:
	_grid_origin = origin
	_grid_resolution = resolution
	
	# Build AStar graph exactly like the player does
	astar_graph.clear()
	cell_to_id.clear()
	var point_id_counter: int = 0
	
	for cell_coord: Vector2i in grid_data:
		astar_graph.add_point(point_id_counter, cell_coord)
		cell_to_id[cell_coord] = point_id_counter
		point_id_counter += 1
		
	for from_cell: Vector2i in grid_data:
		var from_id: int = cell_to_id[from_cell]
		var neighbors_array: Array = grid_data[from_cell]
		for to_cell: Vector2i in neighbors_array:
			if cell_to_id.has(to_cell):
				var to_id: int = cell_to_id[to_cell]
				astar_graph.connect_points(from_id, to_id, false)

func set_patrol_path(points: Array[Vector2i]) -> void:
	
	var scaled_points: Array[Vector2i] = []
	
	var scale_factor = int(_grid_resolution)
	
	for p in points:
		scaled_points.append(p * scale_factor)
	
	patrol_points = scaled_points
	
	current_patrol_index = 0

func _process_patrol_movement() -> void:
	if is_moving: return
	
	# If we have no current path, calculate path to the next patrol point
	if current_path.is_empty():
		var current_cell = _world_to_grid(global_position)
		var target_cell = patrol_points[current_patrol_index]
		
		# If we are already at the target, switch to next target
		if current_cell == target_cell:
			current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
			target_cell = patrol_points[current_patrol_index]
		
		# Calculate A* path
		if cell_to_id.has(current_cell) and cell_to_id.has(target_cell):
			var start_id = cell_to_id[current_cell]
			var end_id = cell_to_id[target_cell]
			current_path = astar_graph.get_point_path(start_id, end_id)
			
			# Remove start point (current pos)
			if current_path.size() > 0:
				current_path.remove_at(0)
	
	# Execute movement
	if not current_path.is_empty():
		_move_to_next_step()

func _move_to_next_step() -> void:
	is_moving = true
	var next_cell = Vector2i(current_path[0])
	current_path.remove_at(0)
	
	var target_pos = _grid_to_world(next_cell)
	
	# Calculate direction towards target (similar to player)
	var direction = (target_pos - global_position).normalized()
	var target_angle = atan2(direction.x, direction.z) + PI  # Add 180° rotation
	
	# Smoothly rotate towards movement direction
	rotation_tween = create_tween()
	rotation_tween.set_parallel(true)  # Run alongside position tween
	
	var current_angle = rotation.y
	var angle_diff = angle_difference(current_angle, target_angle)
	var new_angle = current_angle + angle_diff
	
	rotation_tween.tween_property(self, "rotation:y", new_angle, rotation_duration)
	rotation_tween.set_trans(Tween.TRANS_SINE)
	
	# Create position tween
	active_tween = create_tween()
	active_tween.tween_property(self, "global_position", target_pos, move_duration)
	active_tween.set_trans(Tween.TRANS_LINEAR)
	active_tween.finished.connect(func(): is_moving = false)

func _world_to_grid(world_pos: Vector3) -> Vector2i:
	var grid_x = floori((world_pos.x - _grid_origin.x) * _grid_resolution)
	var grid_z = floori((world_pos.z - _grid_origin.z) * _grid_resolution)
	return Vector2i(grid_x, grid_z)

func _grid_to_world(grid_pos: Vector2i) -> Vector3:
	var world_x = (float(grid_pos.x+0.5) / _grid_resolution) + _grid_origin.x
	var world_z = (float(grid_pos.y+0.5) / _grid_resolution) + _grid_origin.z
	return Vector3(world_x, global_position.y, world_z)

# --- Helpers ---
func update_indicator() -> void:
	if detection_timer > 0:
		var progress = int((detection_timer / detection_time) * 100)
		spot_indicator.text = str(progress) + "%"
		spot_indicator.modulate = Color.WHITE.lerp(Color.RED, detection_timer / detection_time)
	else:
		spot_indicator.text = ""

func game_over() -> void:
	AudioController.stop_walk()
	AudioController.play_lost()
	
	print("GAME OVER")
	spot_indicator.text = "CAUGHT!"
	get_tree().change_scene_to_file("res://scenes/game_over.tscn")
	#set_physics_process(false)

func _set_cone_color(col: Color) -> void:
	vision_cone.color = col

func _on_vision_area_body_entered(body: Node3D) -> void:
	print("on area entered")
	if body is PlayerMovement:
		target_player = body
		is_in_range = true

func _on_vision_area_body_exited(body: Node3D) -> void:
	print("on area exited")
	if body == target_player:
		target_player = null
		is_in_range = false
