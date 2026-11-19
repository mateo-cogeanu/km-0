extends Node
## Two copies of the game on one machine play the road drive together:
## KM0_NET=host starts a lobby, KM0_NET=join joins it on 127.0.0.1. Checks
## the host's story pick reaches the guest, and that an engine takes the two
## of them to lift (coop_net_driver.gd).

var role := ""
var log_lines: Array[String] = []


func _ready() -> void:
	role = OS.get_environment("KM0_NET")
	# Live outside the current scene so the scene change does not free us.
	var driver := Node.new()
	driver.name = "NetDriver"
	driver.set_script(load("res://tools/player_check/coop_net_driver.gd"))
	driver.set("role", role)
	get_tree().root.add_child.call_deferred(driver)
