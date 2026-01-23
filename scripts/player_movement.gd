extends CharacterBody3D
class_name PlayerMovement


const SAVE_FILE_PATH = "user://character_data.json"
const DEAD_ZONE_RATIO: float = 0.125


@export var collision_shape: CollisionShape3D
@export var mesh: MeshInstance3D
@onready var beanie: MeshInstance3D = $CollisionShape3D/Player/Beanie

## How fast the player moves from one cell to the next (in seconds)
@export var move_duration: float = 0.2

## Y-coordinate of the XZ plane to intersect with
@export var ground_plane_y: float = 0.0

## How fast the mesh rotates towards movement direction (in seconds)
@export var rotation_duration: float = 0.15

# Pathfinding graph
var astar_graph = AStar2D.new()

var _grid_origin := Vector3.ZERO
var _grid_resolution: float = 1.0

# Convert between Vector2i grid coords and AStar's integer IDs
var cell_to_id: Dictionary = {}
var id_to_cell: Dictionary = {}

var current_path: PackedVector2Array = []
var is_moving: bool = false
var active_tween: Tween

## Node to hold the debug path markers.
@export var path_markers_container: Node3D

var debug_sphere = SphereMesh.new()

var _player_material: StandardMaterial3D

var points: int = 0

var _last_position: Vector3

func _ready() -> void:
	
	_last_position = global_position

	# 1. Create a material for the player mesh
	_player_material = StandardMaterial3D.new()
	if mesh:
		mesh.set_surface_override_material(0, _player_material)
	else:
		push_error("Player: 'MeshInstance3D' node not found. Check path.")

	# 2. Load the saved appearance data
	_load_character_data()

func _load_character_data() -> void:
	# 1. Check if the save file exists
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		print("Player: No save file found. Using default appearance.")
		return
		
	# 2. Open and read the file content
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if not file:
		push_error("Player: Could not open save file to read.")
		return
		
	var file_content = file.get_as_text()
	file.close()
	
	# 3. Parse the JSON text
	var json = JSON.new()
	var error = json.parse(file_content)
	
	if error != OK:
		push_error("Player: Error parsing save file: %s" % json.get_error_message())
		return

	# 4. Apply the loaded data
	var loaded_data = json.data
	if loaded_data is Dictionary:
		# Get saved values, using defaults if a key is missing
		var new_height = loaded_data.get("height", 2.0)
		var new_radius = loaded_data.get("radius", 0.5)
		var new_color = Color(loaded_data.get("color", "#f7d4a7"))
		
		# Apply to the mesh resource
		if mesh and mesh.mesh is CapsuleMesh:
			mesh.mesh.height = new_height
			mesh.mesh.radius = new_radius
			
			beanie.position = mesh.position + Vector3(0, new_height/2, 0)
			beanie.scale = Vector3.ONE*new_radius/0.5
		
		# Apply to the collision shape resource
		if collision_shape and collision_shape.shape is CapsuleShape3D:
			# IMPORTANT: CapsuleShape height is *only* the cylinder part,
			# but the mesh height is the *total* height. We must convert.
			#collision_shape.shape.height = new_height - (2.0 * new_radius)
			collision_shape.shape.radius = new_radius
			
		# Apply to the material
		if _player_material:
			_player_material.albedo_color = new_color
			
	else:
		push_error("Player: Save file content was not a valid Dictionary.")

func setup_grid_transform(origin: Vector2, resolution: float) -> void:
	_grid_origin = Vector3(origin.x, global_position.y, origin.y)
	_grid_resolution = resolution

func setup_pathfinding_graph(grid_data: Dictionary) -> void:
	astar_graph.clear()
	cell_to_id.clear()
	id_to_cell.clear()
	
	var point_id_counter: int = 0
	
	# Add cells as "points" (nodes) to the graph
	for cell_coord: Vector2i in grid_data:
		astar_graph.add_point(point_id_counter, cell_coord)
		cell_to_id[cell_coord] = point_id_counter
		id_to_cell[point_id_counter] = cell_coord
		point_id_counter += 1
		
	# Add all "connections" (edges)
	for from_cell: Vector2i in grid_data:
		var from_id: int = cell_to_id[from_cell]
		
		var neighbors_array: Array = grid_data[from_cell]
		
		for to_cell: Vector2i in neighbors_array:
			# Make sure the destination cell is also a valid point in our graph
			if cell_to_id.has(to_cell):
				var to_id: int = cell_to_id[to_cell]
				
				astar_graph.connect_points(from_id, to_id, false)

func _process(_delta: float):
	# --- bestehender Klick-Code bleibt UNVERÄNDERT ---
	
	# --- Walk-Sound-Logik ---
	if global_position.distance_to(_last_position) > 0.001:
		AudioController.play_walk()
	else:
		AudioController.stop_walk()
	
	_last_position = global_position
	
	
	if Input.is_action_just_pressed("LeftClick"):
				
		# Get the mouse position and camera
		var mouse_pos = get_viewport().get_mouse_position()
		# normalized and centered mouse position -0.5 to 0.5 
		var normalized_mouse_pos: Vector2 = mouse_pos/get_viewport().get_visible_rect().size - Vector2(0.5, 0.5)
		if (abs(normalized_mouse_pos.y) - (0.5 - DEAD_ZONE_RATIO)) >= 0:
			return
		
		var camera = get_viewport().get_camera_3d()
		
		# Project a ray from the camera
		var ray_origin = camera.project_ray_origin(mouse_pos)
		var ray_direction = camera.project_ray_normal(mouse_pos)
		
		# Calculate intersection with XZ plane at ground_plane_y
		var click_position = _intersect_ray_with_plane(ray_origin, ray_direction, ground_plane_y)
		
		if click_position == null:
			print("No intersection with ground plane.")
			return
		
		# Clear existing path markers
		if path_markers_container:
			for marker in path_markers_container.get_children():
				marker.queue_free()
		
		# Find start and end cells
		var start_cell = _world_to_grid(global_position)
		var end_cell = _world_to_grid(click_position)
		
		# Make sure cells are valid before pathfinding
		if not cell_to_id.has(start_cell) or not cell_to_id.has(end_cell):
			print("Clicked on an invalid or unmapped cell (", click_position, ").")
			return
		
		# Get the integer IDs for AStar
		var start_id: int = cell_to_id[start_cell]
		var end_id: int = cell_to_id[end_cell]
		
		# Calculate the path
		var new_path: PackedVector2Array = astar_graph.get_point_path(start_id, end_id)
		
		# Draw new path markers
		if path_markers_container:
			for i in range(1, new_path.size()):
				var cell_pos: Vector2i = Vector2i(new_path[i])
				var world_pos = _grid_to_world(cell_pos)
				
				var marker_instance = MeshInstance3D.new()
				marker_instance.layers = 2; # 2 = terrain
				marker_instance.mesh = debug_sphere
				marker_instance.scale = Vector3(0.2, 0.2, 0.2)
				path_markers_container.add_child(marker_instance) 
				marker_instance.global_position = world_pos
		
		# Stop all current movement
		if active_tween and active_tween.is_running():
			active_tween.kill()
			is_moving = false
		
		# If the path is just our start, do nothing
		if new_path.size() <= 1:
			current_path.clear()
			return
		
		# Remove the first cell (our current position)
		new_path.remove_at(0)
		
		# Store the new path and start moving
		current_path = new_path
		
		move_to_next_cell()


## Calculates the intersection point of a ray with a horizontal plane
## Returns null if the ray is parallel to the plane or pointing away from it
func _intersect_ray_with_plane(ray_origin: Vector3, ray_direction: Vector3, plane_y: float) -> Variant:
	# Plane equation: y = plane_y
	# Ray equation: P = ray_origin + t * ray_direction
	
	# If ray is parallel to the plane (no y component), no intersection
	if abs(ray_direction.y) < 0.0001:
		return null
	
	# Solve for t: ray_origin.y + t * ray_direction.y = plane_y
	var t = (plane_y - ray_origin.y) / ray_direction.y
	
	# If t is negative, the intersection is behind the camera
	if t < 0:
		return null
	
	# Calculate intersection point
	var intersection = ray_origin + ray_direction * t
	return intersection

func move_to_next_cell() -> void:
	
	# If already moving, or the path is empty, stop.
	if is_moving or current_path.is_empty():
		is_moving = false
		return
		
	is_moving = true
	
	# Get the first cell from the path (as Vector2) and cast it to Vector2i
	var next_cell: Vector2i = Vector2i(current_path[0])
	
	# Remove that cell from the path
	current_path.remove_at(0)
	
	# Convert it to a 3D world position
	var target_position = _grid_to_world(next_cell)
	
	# Calculate direction towards target
	var direction = (target_position - global_position).normalized()
	var target_angle = atan2(direction.x, direction.z)
	
	# Rotate mesh towards movement direction
	if mesh:
		var rotation_tween = create_tween()
		rotation_tween.set_parallel(true)  # Run alongside position tween
		
		# Smoothly rotate towards target direction
		var current_angle = mesh.rotation.y
		var angle_diff = angle_difference(current_angle, target_angle)
		var new_angle = current_angle + angle_diff
		
		rotation_tween.tween_property(mesh, "rotation:y", new_angle, rotation_duration)
		rotation_tween.set_trans(Tween.TRANS_SINE)
	
	# Create a tween to move there
	active_tween = create_tween()
	active_tween.tween_property(self, "global_position", target_position, move_duration)
	active_tween.set_trans(Tween.TRANS_SINE)
	
	# When this tween finishes, it will call this function again
	# to move to the *next* cell in the path.
	# When the tween finishes, first set is_moving to false,
	# *then* call move_to_next_cell() to start the next step.
	active_tween.finished.connect(func():
		is_moving = false
		move_to_next_cell()
	)

# Converts a 3D world position to a 2D grid coordinate
func _world_to_grid(world_pos: Vector3) -> Vector2i:
	var grid_x = floori((world_pos.x - _grid_origin.x) * _grid_resolution)
	var grid_z = floori((world_pos.z - _grid_origin.z) * _grid_resolution)
	return Vector2i(grid_x, grid_z)

# Converts a 2D grid coordinate to a 3D world position
func _grid_to_world(grid_pos: Vector2i) -> Vector3:
	var world_x = (float(grid_pos.x+0.5) / _grid_resolution) + _grid_origin.x
	var world_z = (float(grid_pos.y+0.5) / _grid_resolution) + _grid_origin.z
	return Vector3(world_x, 0.0, world_z)

func add_points(value: int) -> void:
	points += value;
	points = max(0, points)

## Teleports the player to the nearest valid grid cell to the given world position
func teleport_to_nearest_cell(target_world_pos: Vector3) -> void:
	# Convert target position to grid coordinates
	var target_grid_pos: Vector2i = _world_to_grid(target_world_pos)
	
	# Find the nearest valid cell in the pathfinding graph
	var nearest_cell: Vector2i = target_grid_pos
	var min_distance: float = INF
	
	for valid_cell in cell_to_id.keys():
		var distance: float = target_grid_pos.distance_to(valid_cell)
		if distance < min_distance:
			min_distance = distance
			nearest_cell = valid_cell
	
	# Cancel any ongoing movement
	if active_tween and active_tween.is_running():
		active_tween.kill()
	
	is_moving = false
	current_path.clear()
	
	# Teleport to the nearest valid cell
	var world_position = _grid_to_world(nearest_cell)
	global_position = world_position
	_last_position = global_position
