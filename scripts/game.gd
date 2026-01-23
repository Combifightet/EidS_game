extends Control

var floorplan_gen: FloorPlanGen

@export var player_node: PlayerMovement
## should be of type `enum FloorPlanGen.HouseSize`

const GRID_SUBDIVISIONS: int = 1

@onready var progress_bar: TextureProgressBar = $LoadingScreen/ColorRect/ProgressBar
@onready var loading_screen: Control = $LoadingScreen
@onready var level_gen: LevelGen = %PixelViewport/Level
var elapsed: float = 0

var tween: Tween
var animation_duration: float = 1.5

var world: WorldGen
var connectivity: Dictionary[Vector2i, Array]

func _ready() -> void:
	print("game loaded")
	start_loading_animation()

func _process(delta: float) -> void:
	if elapsed <= 0.5:
		elapsed += delta
		if elapsed >= 0.5:
			print("setting up level")
			var thread = Thread.new()
			thread.start(_setup_level)
			#_setup_level()
			#print("level setup complete")
			

func start_loading_animation() -> void:
	loading_screen.visible = true
	progress_bar.value = 0
	
	# Kill any existing tween
	if tween:
		tween.kill()
	
	# Create looping tween animation
	tween = create_tween()
	tween.set_loops()  # Loop infinitely
	tween.tween_property(progress_bar, "value", progress_bar.max_value, animation_duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(progress_bar, "value",  progress_bar.min_value, animation_duration).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func stop_loading_animation() -> void:
	var patrol_points = level_gen.from_grid(
		%Player,
		world.grid,
		world.doors,
		GRID_SUBDIVISIONS
	)
	
	level_gen.place_guards(
		world.grid, 
		player_node, 
		connectivity, 
		Vector3(world.grid.origin.x, 0, world.grid.origin.y), 
		world.grid.grid_resolution,
		patrol_points
	)
	print("finished level setup")
	
	await get_tree().create_timer(0.5).timeout
	
	if tween:
		tween.kill()
	loading_screen.visible = false

func setup_grid_transform(origin: Vector2, resolution: float) -> void:
	player_node.setup_grid_transform(origin, resolution)

func set_player_global_position(pos: Vector3) -> void:
	player_node.global_position = pos

func set_level_gen_position(pos: Vector3) -> void:
	level_gen.position = pos

func _setup_level() -> void:
	floorplan_gen = FloorPlanGen.new()
	#floorplan_gen.set_seed(7)
	randomize()
	floorplan_gen.set_seed(randi())
	floorplan_gen.generate(Global.difficulty)
	print("last_seed: ", floorplan_gen.get_last_seed())
	
	print("displaying grid ...")
	var grid: FloorPlanGrid = floorplan_gen.get_grid()

	# overwrite the old grid with the generated surroundings
	world = WorldGen.new(grid, floorplan_gen._doors_list, floorplan_gen.building_outline)
		
	# --- Setup the Player ---
	var connectivity_og: Dictionary[Vector2i, Array] = FloorPlanGen.get_connectivity_dict(world.grid, world.doors)
	connectivity = FloorPlanGen.get_connectivity_dict(world.grid, world.doors, GRID_SUBDIVISIONS)
	
	if not player_node:
		printerr("Player node not assigned in main.gd!")
		call_deferred("stop_loading_animation")
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	
	# Pass the grid's transform and connectivity data to the player
	#player_node.setup_grid_transform(world.grid.origin, world.grid.grid_resolution)
	call_deferred("setup_grid_transform", world.grid.origin, world.grid.grid_resolution)
	player_node.setup_pathfinding_graph(connectivity)
	
# 1. Get all valid, walkable cells from the connectivity data
	var valid_cells: Array[Vector2i] = connectivity.keys() 
	
	valid_cells.sort_custom(func(a, b):
		if a.x == b.x:
			return a.y < b.y
		return a.x < b.x
	)
	
	var top_left_cell: Vector2i = valid_cells[0]
	
	# 3. Get the grid's transform data
	var grid_origin: Vector2 = world.grid.origin
	var grid_resolution: float = world.grid.grid_resolution
	
	# 4. Calculate the 3D world position (using logic from playerMovement.gd)
	var world_x = (float(top_left_cell.x) / grid_resolution) + grid_origin.x
	var world_z = (float(top_left_cell.y) / grid_resolution) + grid_origin.y
	
	# 5. Set the player's position, using the correct height
	#player_node.global_position = Vector3(world_x, 0.7, world_z)
	call_deferred("set_player_global_position", Vector3(world_x, 0.7, world_z))
	
	# --- This console debug print is still useful ---
	FloorPlanGrid.print_grid(world.grid)
	
	#print("\n\nconnectivity:")
	#print(dict_connections_to_grid_string(connectivity))
	print("\n\nconnectivity (original):")
	print(dict_connections_to_grid_string(connectivity_og))
	
	
	#level_gen.position = Vector3(world.grid.origin.x, 0, world.grid.origin.y)
	call_deferred("set_level_gen_position", Vector3(world.grid.origin.x, 0, world.grid.origin.y))
	
	call_deferred("stop_loading_animation")



func dict_connections_to_grid_string(connections: Dictionary) -> String:
	if connections.is_empty():
		return "No connections"
	
	# Find grid bounds
	var max_x = 0
	var max_y = 0
	
	for pos in connections.keys():
		max_x = max(max_x, pos.x)
		max_y = max(max_y, pos.y)
	
	# Create grid (3x3 per cell: node + connection spaces)
	var width = max_x * 2 + 1
	var height = max_y * 2 + 1
	var grid = []
	for y in range(height + 1):
		var row = []
		for x in range(width + 1):
			row.append(" ")
		grid.append(row)
	
	# Place all nodes
	for pos in connections.keys():
		var gx = pos.x * 2
		var gy = pos.y * 2
		grid[gy][gx] = "●"
	
	# Draw connections
	for pos in connections.keys():
		var gx = pos.x * 2
		var gy = pos.y * 2
		
		for neighbor in connections[pos]:
			var diff = neighbor - pos
			
			# Right (1, 0)
			if diff.x == 1 and diff.y == 0:
				grid[gy][gx + 1] = "─"
			
			# Down (0, 1)
			elif diff.x == 0 and diff.y == 1:
				grid[gy + 1][gx] = "│"
			
			# Diagonal down-right (1, 1)
			elif diff.x == 1 and diff.y == 1:
				if grid[gy + 1][gx + 1] == "╱":
					grid[gy + 1][gx + 1] = "╳"
				elif grid[gy + 1][gx + 1] != "╳":
					grid[gy + 1][gx + 1] = "╲"
			
			# Diagonal up-right (1, -1)
			elif diff.x == 1 and diff.y == -1:
				if grid[gy - 1][gx + 1] == "╲":
					grid[gy - 1][gx + 1] = "╳"
				elif grid[gy - 1][gx + 1] != "╳":
					grid[gy - 1][gx + 1] = "╱"
			
			# Left (-1, 0)
			elif diff.x == -1 and diff.y == 0:
				grid[gy][gx - 1] = "─"
			
			# Up (0, -1)
			elif diff.x == 0 and diff.y == -1:
				grid[gy - 1][gx] = "│"
			
			# Diagonal down-left (-1, 1)
			elif diff.x == -1 and diff.y == 1:
				if grid[gy + 1][gx - 1] == "╲":
					grid[gy + 1][gx - 1] = "╳"
				elif grid[gy + 1][gx - 1] != "╳":
					grid[gy + 1][gx - 1] = "╱"
			
			# Diagonal up-left (-1, -1)
			elif diff.x == -1 and diff.y == -1:
				if grid[gy - 1][gx - 1] == "╱":
					grid[gy - 1][gx - 1] = "╳"
				elif grid[gy - 1][gx - 1] != "╳":
					grid[gy - 1][gx - 1] = "╲"
	
	# Convert grid to string
	var result = ""
	for y in range(height + 1):
		for x in range(width + 1):
			result += grid[y][x]
		result += "\n"
	
	return result
