extends RigidBody3D

@export var max_fuel: float = 20.0
@export var fuel_amount: float = 20.0


func _ready() -> void:
	add_to_group("fuel_canister")


func get_fuel_fraction() -> float:
	if max_fuel <= 0.0:
		return 0.0

	return clampf(fuel_amount / max_fuel, 0.0, 1.0)


func drain_fuel(amount: float) -> float:
	var drained := minf(maxf(amount, 0.0), fuel_amount)
	fuel_amount -= drained
	return drained
