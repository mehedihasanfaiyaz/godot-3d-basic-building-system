extends StaticBody3D

@export var territory_size: float = 44.0
@onready var area_indicator = $AreaIndicator

func _ready():
	add_to_group("territory")
	# If we have a visual indicator for the size, scale it
	if area_indicator:
		# Make mesh unique so we don't affect other instances if we change size
		area_indicator.mesh = area_indicator.mesh.duplicate()
		area_indicator.mesh.size = Vector3(territory_size, 0.1, territory_size)
		
		# If it's a shader material, we can pass parameters
		if area_indicator.mesh.material is ShaderMaterial:
			area_indicator.mesh.material = area_indicator.mesh.material.duplicate()
			area_indicator.mesh.material.set_shader_parameter("territory_size", territory_size)

func is_within_territory(pos: Vector3) -> bool:
	var local_pos = pos - global_position
	var half_size = territory_size / 2.0
	return abs(local_pos.x) <= half_size + 0.1 and abs(local_pos.z) <= half_size + 0.1
