extends Control

var floorplan_gen: FloorPlanGen

@export var player_node: PlayerMovement
## should be of type `enum FloorPlanGen.HouseSize`

const GRID_SUBDIVISIONS: int = 1


func _ready() -> void:

	
	floorplan_gen = FloorPlanGen.new()
	#floorplan_gen.set_seed(7)
	randomize()
	floorplan_gen.set_seed(randi())
	floorplan_gen.generate(Global.difficulty)
	print("last_seed: ", floorplan_gen.get_last_seed())
	
	print("displaying grid ...")
	var grid: FloorPlanGrid = floorplan_gen.get_grid()

	# overwrite the old grid with the generated surroundings
	var world: WorldGen = WorldGen.new(grid, floorplan_gen._doors_list, floorplan_gen.building_outline)
		
	# --- Setup the Player ---
	var connectivity_og: Dictionary[Vector2i, Array] = FloorPlanGen.get_connectivity_dict(world.grid, world.doors)
	var connectivity: Dictionary[Vector2i, Array] = FloorPlanGen.get_connectivity_dict(world.grid, world.doors, GRID_SUBDIVISIONS)
	
	if not player_node:
		printerr("Player node not assigned in main.gd!")
		return
		
	# Pass the grid's transform and connectivity data to the player
	player_node.setup_grid_transform(world.grid.origin, world.grid.grid_resolution)
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
	player_node.global_position = Vector3(world_x, 0.7, world_z)
	
	# --- This console debug print is still useful ---
	FloorPlanGrid.print_grid(world.grid)
	
	#print("\n\nconnectivity:")
	#print(dict_connections_to_grid_string(connectivity))
	print("\n\nconnectivity (original):")
	print(dict_connections_to_grid_string(connectivity_og))
	
	var level_gen: LevelGen = %PixelViewport/Level
	level_gen.position = Vector3(world.grid.origin.x, 0, world.grid.origin.y)
	
	var patrol_points = level_gen.from_grid(world.grid, world.doors, GRID_SUBDIVISIONS)
	
	level_gen.place_single_guard(
		world.grid, 
		player_node, 
		connectivity, 
		Vector3(world.grid.origin.x, 0, world.grid.origin.y), 
		world.grid.grid_resolution,
		patrol_points
	)



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
