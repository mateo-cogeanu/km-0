extends Node
## Two copies of the game on one machine play the Salvage Run together:
## KM0_NET=host starts a lobby, KM0_NET=join joins it on 127.0.0.1. Checks
## both players and the creature are in sync, carrying an engine between two
## players, being grabbed and let go, and the night ending for both.

var role := ""
var log_lines: Array[String] = []


func _ready() -> void:
	role = OS.get_environment("KM0_NET")
	# Live outside the current scene so the scene change does not free us.
	var driver := Node.new()
	driver.name = "NetDriver"
	driver.set_script(load("res://tools/player_check/salvage_net_driver.gd"))
	driver.set("role", role)
	get_tree().root.add_child.call_deferred(driver)
