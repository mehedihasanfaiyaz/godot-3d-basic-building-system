extends RayCast3D

class_name RaycastWheel

## Suspension Properties
@export_group("Suspension")
@export var spring_strength := 100000.0
@export var spring_damping := 2500.0
@export var rest_distance := 0.5
@export var over_extend := 0.0
@export var wheel_radius := 0.4

## Wheel Type
@export_group("Wheel Type")
@export var is_motor := false
@export var is_steerable := false

## Friction Properties
@export_group("Friction")
@export var tire_grip := 2.5
@export var longitudinal_grip := 4.0
@export var lateral_stiffness := 60.0   # How fast the tire bites (INCREASED to 60.0)
@export var rolling_resistance := 0.5

## Visual
@export var visual_y_offset := 0.0
@onready var wheel_mesh: Node3D = get_node_or_null("wheel")
@onready var shape_cast: ShapeCast3D = get_node_or_null("ShapeCast3D")

## State
var current_compression := 0.0
var previous_compression := 0.0
var is_grounded := false
var is_slipping := false
var contact_point := Vector3.ZERO
var contact_normal := Vector3.UP
var visual_radius: float = 0.0

var vehicle_body: RigidBody3D

func _ready() -> void:
	# MASK 5: Collide with World (1) and Structures (4)
	collision_mask = 5
	
	vehicle_body = get_parent() as RigidBody3D
	if not vehicle_body: return

	# Force-align wheel mesh to axle center
	if wheel_mesh:
		wheel_mesh.position.x = 0
		wheel_mesh.position.z = 0
		# Detect true visual radius from entire child hierarchy
		visual_radius = _detect_max_radius(wheel_mesh)
		
		# If physics radius is default 0.4, sync it with visuals
		if is_equal_approx(wheel_radius, 0.4) and visual_radius > 0:
			wheel_radius = visual_radius
			
		#print("RaycastWheel: %s | Radius: %.3f (Vis) | %.3f (Phys)" % [name, visual_radius, wheel_radius])

	# Setup Sensors
	var reach = rest_distance + wheel_radius + over_extend
	target_position = Vector3(0, -reach, 0)
	enabled = true
	
	if shape_cast:
		shape_cast.enabled = true
		shape_cast.collision_mask = 5
		shape_cast.add_exception(vehicle_body)
		# Force ShapeCast to Axel Center (0,0,0)
		shape_cast.position = Vector3.ZERO
		# Local X is Down due to -90deg X rotation in scene
		shape_cast.target_position = Vector3(-reach, 0, 0)
		if shape_cast.shape is CylinderShape3D:
			shape_cast.shape.radius = wheel_radius
		shape_cast.force_shapecast_update()

func _detect_max_radius(node: Node3D) -> float:
	var max_r = 0.0
	if node is MeshInstance3D and node.mesh:
		var aabb = node.mesh.get_aabb()
		var size = aabb.size * node.scale
		max_r = max(size.x, max(size.y, size.z)) * 0.5
	
	for child in node.get_children():
		if child is Node3D:
			max_r = max(max_r, _detect_max_radius(child))
	return max_r

func process_wheel_physics(
	delta: float,
	steer_input: float,
	throttle_reverse: float,
	brake: float,
	engine_force: float,
	brake_force_f: float,
	grip_modifier: float = 1.0 # Added for global grip control (drift/ice)
) -> Dictionary:
	_update_collision()
	_update_visual(delta)
	
	is_slipping = false # Reset every frame
	
	if is_grounded:
		_calculate_suspension_force(delta)
		_apply_friction(steer_input, throttle_reverse, brake, engine_force, brake_force_f, grip_modifier)
		
	return {
		"grounded": is_grounded, 
		"compression": current_compression,
		"slipping": is_slipping
	}

func _update_collision() -> void:
	if shape_cast and shape_cast.is_enabled():
		shape_cast.force_shapecast_update()
		if shape_cast.is_colliding():
			is_grounded = true
			contact_point = shape_cast.get_collision_point(0)
			contact_normal = shape_cast.get_collision_normal(0)
			_calculate_compression()
			return
	
	force_raycast_update()
	is_grounded = is_colliding()
	if is_grounded:
		contact_point = get_collision_point()
		contact_normal = get_collision_normal()
		_calculate_compression()
	else:
		current_compression = 0.0
		contact_point = global_position - (global_basis.y * (rest_distance + wheel_radius))
		contact_normal = Vector3.UP

func _calculate_vertical_dist() -> float:
	# Calculate distance from axle (axle mount) to ground ALONG the suspension Up axis
	var to_contact = contact_point - global_position
	return abs(to_contact.dot(global_basis.y))

func _calculate_compression():
	var dist = _calculate_vertical_dist()
	# spring_len is how long the spring is (distance from axle to tire top)
	var spring_len = dist - wheel_radius
	# Compression is Rest - Current. (e.g. 0.5 - 0.3 = 0.2 compressed).
	current_compression = clamp(rest_distance - spring_len, 0.0, rest_distance)

func _calculate_suspension_force(delta: float) -> float:
	var spring_force = current_compression * spring_strength
	
	# Clamp compression velocity to prevent damping explosions during impacts
	var raw_vel = (current_compression - previous_compression) / delta
	var safe_vel = clamp(raw_vel, -10.0, 10.0) 
	var damper_force = safe_vel * spring_damping
	previous_compression = current_compression
	
	var total_force = max(0.0, spring_force + damper_force)
	
	var push_vector = global_basis.y * total_force
	var rel_pos = global_position - vehicle_body.global_position
	vehicle_body.apply_force(push_vector, rel_pos)
	
	return total_force

func _apply_friction(steer, throttle_reverse, brake, engine, brake_f, grip_mod):
	var tire_fwd = -global_basis.z.rotated(global_basis.y, steer)
	var tire_right = global_basis.x.rotated(global_basis.y, steer)
	
	var rel_pos = global_position - vehicle_body.global_position
	var world_vel = vehicle_body.linear_velocity + vehicle_body.angular_velocity.cross(rel_pos)
	
	# Calculate total load (Normal Force) the suspension supports
	var normal_force = current_compression * spring_strength
	if normal_force <= 0: return # No friction without contact pressure
	
	# Dynamic Grip
	var current_tire_grip = tire_grip * grip_mod
	
	# === LONGITUDINAL (Drive/Brake) ===
	var drive_force_vec = Vector3.ZERO
	if is_motor:
		drive_force_vec = tire_fwd * throttle_reverse * engine
	
	# Braking
	var brake_force_vec = Vector3.ZERO
	if brake > 0:
		var fwd_speed = tire_fwd.dot(world_vel)
		brake_force_vec = -tire_fwd * sign(fwd_speed) * brake * brake_f
	
	# Total Longitudinal Limit (Coulomb Friction)
	var total_long_force = drive_force_vec + brake_force_vec
	var max_long_grip = normal_force * longitudinal_grip * grip_mod
	if total_long_force.length() > max_long_grip:
		total_long_force = total_long_force.normalized() * max_long_grip
		is_slipping = true
	
	vehicle_body.apply_force(total_long_force, rel_pos)
	
	# === LATERAL (Slide Prevention) ===
	var lat_vel = tire_right.dot(world_vel)
	var fwd_vel = abs(tire_fwd.dot(world_vel))
	
	# Pro Tip: Use atan for a smooth friction curve (Simplified Pacejka)
	# This allows the tire to "slip" and then lose grip naturally
	var slip_angle = atan2(lat_vel, max(fwd_vel, 1.0)) 
	var lat_force_mag = -slip_angle * lateral_stiffness * (vehicle_body.mass / 4.0)
	
	# Cap by normal force
	var max_lat_grip = normal_force * current_tire_grip
	if abs(lat_force_mag) > max_lat_grip:
		lat_force_mag = sign(lat_force_mag) * max_lat_grip
		is_slipping = true
		
	vehicle_body.apply_force(tire_right * lat_force_mag, rel_pos)

func _update_visual(delta: float) -> void:
	if not wheel_mesh: return
	
	var target_y := 0.0
	var r = visual_radius if visual_radius > 0 else wheel_radius
	
	if is_grounded:
		var dist = _calculate_vertical_dist()
		# Position mesh so bottom (center - r) is at ground (-dist)
		# Center Y = -dist + r
		target_y = -dist + r + visual_y_offset
	else:
		# Sit at rest (maximal extension)
		target_y = -(rest_distance + over_extend) + wheel_radius + visual_y_offset

	# Lock position (Interpolate smoothly but quickly)
	wheel_mesh.position.y = lerp(wheel_mesh.position.y, target_y, 45.0 * delta)
	
	# Steer sync
	if shape_cast:
		shape_cast.rotation.y = wheel_mesh.rotation.y

	# Rolling effect
	if vehicle_body:
		var fwd_vel = -global_basis.z.dot(vehicle_body.linear_velocity)
		# Correct for reversed rotation
		wheel_mesh.rotate_x(-(fwd_vel / r) * delta)
		
	# DEBUG CHECK
	if name == "wheelFL" and Engine.get_physics_frames() % 60 == 0:
		var actual_dist = _calculate_vertical_dist()
		var mesh_bottom = wheel_mesh.global_position.y - r
		var gap = mesh_bottom - contact_point.y
		#print("WHEEL DEBUG | Dist: %.2f | Gap: %.4f | Comp: %.2f | VisR: %.2f" % [actual_dist, gap, current_compression, r])


func get_compression_ratio() -> float:
	return current_compression / rest_distance if rest_distance > 0 else 0.0

func is_wheel_grounded() -> bool:
	return is_grounded
