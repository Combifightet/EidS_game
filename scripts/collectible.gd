extends Node3D
class_name Collectible

@export_range(10, 30, 1, "or_less", "or_greater") var value: float = 23

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Area3D/Gold.scale = Vector3.ONE * (value/30.0)
	
	$Area3D.body_entered.connect(_on_body_entered)

	

func _on_body_entered(body: Node3D) -> void:
	
	AudioController.play_collectible()
	
	# Check if the entering area belongs to the player and has add_points method
	if body and body.has_method("add_points"):
		body.add_points(int(value))
		
		$Area3D.set_deferred("monitoring", false)
		# could play a sound or animation here befor freeing
		$Area3D.call_deferred("queue_free")
