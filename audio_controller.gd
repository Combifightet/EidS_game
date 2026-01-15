extends Node2D

@export var mute: bool = false

func _ready():
	if not mute:
		play_music()
		
func play_music():
	if not mute:
		$Music.play()
		
func play_walk():
	if not $Walk.playing:
		$Walk.play()

func stop_walk():
	if $Walk.playing:
		$Walk.stop()
		
func play_collectible():
	if not mute:
		$Collectible.play()
		
func play_lost():
	if not mute:
		$Lost.play()
		
func play_seen():
	if not mute:
		$Seen.play()
