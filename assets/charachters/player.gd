extends CharacterBody3D

@export_group("Movement")
@export var speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var rotation_speed: float = 12.0

@export_group("Camera")
# ... (rest of camera exports)
@export var mouse_sensitivity: float = 0.002
@export var min_tilt: float = -80.0
@export var max_tilt: float = 80.0

@export_group("Survival Stats")
@export var max_health: float = 100.0
@export var fall_damage_threshold: float = -12.0 # Velocity at which damage starts
@export var fall_damage_multiplier: float = 5.0
@export var max_hunger: float = 100.0
@export var max_thirst: float = 100.0
@export var max_sanity: float = 100.0
@export var max_energy: float = 100.0

@export var hunger_depletion_rate: float = 0.5 
@export var thirst_depletion_rate: float = 0.8 
@export var sanity_depletion_rate: float = 0.2 
@export var energy_depletion_rate: float = 15.0 # Per second while sprinting
@export var energy_restoration_rate: float = 10.0 # Per second while not sprinting

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var armature: Node3D = $Armature
@onready var cam_horizontal: Node3D = $cam_horizhontal
@onready var cam_vertical: Node3D = $cam_horizhontal/cam_vertical
@onready var camera: Camera3D = $cam_horizhontal/cam_vertical/Camera3D

@export var hud_scene: PackedScene = load("res://assets/charachters/player_hud.tscn")
var hud_instance

var current_interact_target = null
var nearby_scan_timer = 0.0
var nearby_scan_interval = 0.2
var building_system: Node3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_crouching: bool = false
var is_sprinting: bool = false
var was_on_floor: bool = true
var is_dead: bool = false
var is_rolling: bool = false
var is_exhausted: bool = false
var previous_y_velocity: float = 0.0
var is_driving: bool = false
var is_building: bool = false
var has_territory: bool = false
var is_flying: bool = false
var fly_speed: float = 12.0
var fly_cam: Camera3D
var current_vehicle: RigidBody3D = null
var inventory_data: InventoryData

var current_health: float
var current_hunger: float
var current_thirst: float
var current_sanity: float
var current_energy: float

signal stats_updated(health: float, hunger: float, thirst: float, sanity: float, energy: float)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	current_health = max_health
	current_hunger = max_hunger
	current_thirst = max_thirst
	current_sanity = max_sanity
	current_energy = max_energy
	
	# Ensure collision with Bit 3 (STRUCTURES)
	collision_mask |= 8
	
	# Initialize Inventory
	inventory_data = InventoryData.new()
	for i in range(24):
		var slot = InventorySlot.new()
		inventory_data.slots.append(slot)
	
	# Setup UI
	if hud_scene:
		hud_instance = hud_scene.instantiate()
		add_child(hud_instance)
		hud_instance.setup(self)

	# Setup Building System
	if not building_system:
		building_system = Node3D.new()
		building_system.name = "BuildingSystem"
		building_system.set_script(load("res://building/building_system.gd"))
		add_child(building_system)

	# Setup Fly Camera
	fly_cam = Camera3D.new()
	add_child(fly_cam)
	fly_cam.current = false

	animation_player.animation_finished.connect(_on_animation_finished)
	stats_updated.emit(current_health, current_hunger, current_thirst, current_sanity, current_energy)

func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
		
	#if is_building and event is InputEventKey and event.pressed:
		#print("Build mode active - key pressed: ", event.as_text())
		
	# 1. PRIORITY INPUTS (Camera, Escape, Inventory, Build Toggle)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if hud_instance and not hud_instance.emote_wheel.visible:
			var inv = hud_instance.get_node_or_null("%MainInventory")
			var b_menu = hud_instance.get_node_or_null("%BuildMenuUI")
			if (not inv or not inv.visible) and (not b_menu or not b_menu.visible):
				rotate_camera(event.relative)
	
	if event.is_action_pressed("ui_cancel"):
		if is_building:
			toggle_build_mode()
			return # Consume the input
			
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			
	if event.is_action_pressed("toggle_inv"):
		if hud_instance:
			hud_instance.toggle_inventory()
			
	if event.is_action_pressed("build_mode"):
		toggle_build_mode()
		return
		
	if is_building and event.is_action_pressed("fly_mode"):
		print("Fly mode key pressed! Current is_flying: ", is_flying)
		toggle_fly_mode()
		return

	if is_building and event.is_action_pressed("build_menu"):
		# Always deselect blueprint if active
		if is_instance_valid(building_system) and building_system.current_blueprint != null:
			building_system.select_blueprint(null)
			
		# Always open the menu immediately
		if hud_instance:
			hud_instance.toggle_build_menu()
		return

	# 2. STATE-SPECIFIC BLOCKS
	if is_building:
		building_system.handle_input(event)
		if not is_flying:
			return

	# 3. GAMEPLAY INTERACTIONS
	if event.is_action_pressed("emote_wheel"):
		if hud_instance:
			hud_instance.set_emote_wheel_visible(true)
	elif event.is_action_released("emote_wheel"):
		if hud_instance:
			hud_instance.set_emote_wheel_visible(false)
	
	# do not fucking change the "veh_toggle"
	if event.is_action_pressed("veh_toggle"):
		if is_driving:
			exit_vehicle()
		else:
			_try_enter_vehicle()
	
	if event.is_action_pressed("player_pickup") or event.is_action_pressed("player_interact"):
		_try_pickup_item()

func _update_interaction(delta: float):
	# 1. Raycast to find what player is looking at
	var space_state = get_world_3d().direct_space_state
	var viewport_size = get_viewport().get_visible_rect().size
	var mouse_pos = viewport_size / 2
	var origin = camera.project_ray_origin(mouse_pos)
	var end = origin + camera.project_ray_normal(mouse_pos) * 4.0
	var query = PhysicsRayQueryParameters3D.create(origin, end)
	# MASK 15: World (1), Items (2), Vehicles (4), Structures (8)
	query.collision_mask = 1 | 2 | 4 | 8 
	
	var result = space_state.intersect_ray(query)
	var new_target = null
	if result:
		new_target = result.collider
	
	if new_target != current_interact_target:
		current_interact_target = new_target
		if hud_instance:
			hud_instance.update_interact_info(current_interact_target)
	
	# 2. Scanning nearby items
	nearby_scan_timer += delta
	if nearby_scan_timer >= nearby_scan_interval:
		nearby_scan_timer = 0.0
		_scan_nearby()

func _scan_nearby():
	var overlap_radius = 8.0
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = SphereShape3D.new()
	shape.radius = overlap_radius
	query.shape_rid = shape.get_rid()
	query.transform = global_transform
	query.collision_mask = 2 # Only Items layer
	
	var results = space_state.intersect_shape(query, 10)
	var items = []
	for res in results:
		if res.collider.has_method("interact"):
			items.append(res.collider)
	
	if is_building:
		if hud_instance: hud_instance.update_nearby_items([])
		return
		
	if hud_instance:
		hud_instance.update_nearby_items(items)

func _try_enter_vehicle() -> void:
	if current_interact_target and current_interact_target.has_method("enter_vehicle"):
		current_interact_target.enter_vehicle(self)
		return

	# Proximity fallback (Layer 1: Vehicles)
	var overlap_radius = 3.0
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = SphereShape3D.new()
	shape.radius = overlap_radius
	query.shape_rid = shape.get_rid()
	query.transform = global_transform
	query.collision_mask = 1 
	
	var results = space_state.intersect_shape(query)
	for result in results:
		if result.collider.has_method("enter_vehicle"):
			result.collider.enter_vehicle(self)
			return

func _try_pickup_item() -> void:
	if current_interact_target and current_interact_target.has_method("interact"):
		current_interact_target.interact(self)
		return

	# Proximity fallback (Layer 2: Items)
	var overlap_radius = 3.0
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = SphereShape3D.new()
	shape.radius = overlap_radius
	query.shape_rid = shape.get_rid()
	query.transform = global_transform
	query.collision_mask = 2 
	
	var results = space_state.intersect_shape(query)
	for result in results:
		if result.collider.has_method("interact"):
			result.collider.interact(self)
			return

func rotate_camera(relative: Vector2) -> void:
	if is_flying:
		fly_cam.rotate_y(-relative.x * mouse_sensitivity)
		fly_cam.rotate_object_local(Vector3.RIGHT, -relative.y * mouse_sensitivity)
		# Clamp pitch
		var rot = fly_cam.rotation
		rot.x = clamp(rot.x, deg_to_rad(-85), deg_to_rad(85))
		fly_cam.rotation = rot
	else:
		cam_horizontal.rotate_y(-relative.x * mouse_sensitivity)
		cam_vertical.rotate_x(-relative.y * mouse_sensitivity)
		cam_vertical.rotation.x = clamp(cam_vertical.rotation.x, deg_to_rad(min_tilt), deg_to_rad(max_tilt))

func _physics_process(delta: float) -> void:
	# 0. Handle Survival Depletion
	_process_survival_stats(delta)

	if is_flying:
		_process_fly_mode(delta)
		return

	# Block movement if inventory is open
	if hud_instance and hud_instance.get_node_or_null("%MainInventory") and hud_instance.get_node("%MainInventory").visible:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
		move_and_slide()
		return

	if is_dead or is_driving:
		return

	# 1. Update Interaction Ray (Only if not building)
	if not is_building:
		_update_interaction(delta)
	else:
		# Clear interaction target when building
		if current_interact_target != null:
			current_interact_target = null
			if hud_instance: hud_instance.update_interact_info(null)

	# 1. Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. Jump
	if Input.is_action_just_pressed("player_jump") and is_on_floor():
		velocity.y = jump_velocity
		animation_player.play("Jump_Start")

	# 3. Input, Speed, and Sprint
	is_crouching = Input.is_action_pressed("player_crouch")
	
	if Input.is_action_just_pressed("player_sprint") and is_on_floor() and not is_crouching and not is_rolling and not is_exhausted:
		is_rolling = true
		animation_player.play("Roll")
	
	is_sprinting = Input.is_action_pressed("player_sprint") and not is_crouching and current_energy > 0.0 and not is_exhausted
	
	var current_speed = speed
	if is_crouching:
		current_speed = speed * 0.5
	elif is_sprinting or is_rolling:
		current_speed = sprint_speed
		
	var input_dir := Input.get_vector("player_left", "player_right", "player_forward", "player_backward")
	
	# 4. ROBUST DIRECTION CALCULATION
	# Get the camera's orientation vectors, ignoring vertical tilt
	var camera_basis = cam_horizontal.global_transform.basis
	var forward_vec = -camera_basis.z.normalized() 
	var right_vec = camera_basis.x.normalized()     
	
	# Calculate final move direction
	var direction = (forward_vec * -input_dir.y + right_vec * input_dir.x).normalized()
	direction.y = 0
	direction = direction.normalized()

	# 5. Apply Movement and Visual Rotation
	if direction.length() > 0.1:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
		
		var target_angle = atan2(direction.x, direction.z)
		armature.rotation.y = lerp_angle(armature.rotation.y, target_angle, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	# 6. Animation and Physics Update
	update_animations(input_dir)
	
	# Fall Damage Logic
	if is_on_floor() and not was_on_floor:
		if previous_y_velocity < fall_damage_threshold:
			var damage = abs(previous_y_velocity - fall_damage_threshold) * fall_damage_multiplier
			take_damage(damage)
	
	move_and_slide()
	
	was_on_floor = is_on_floor()
	previous_y_velocity = velocity.y

func take_damage(amount: float):
	if is_dead: return
	current_health = max(0.0, current_health - amount)
	if current_health <= 0.0:
		die()
	stats_updated.emit(current_health, current_hunger, current_thirst, current_sanity, current_energy)

func _process_survival_stats(delta: float) -> void:
	if is_dead:
		return

	# Deplete stats
	current_hunger = max(0.0, current_hunger - hunger_depletion_rate * delta)
	current_thirst = max(0.0, current_thirst - thirst_depletion_rate * delta)
	current_sanity = max(0.0, current_sanity - sanity_depletion_rate * delta)
	
	# Energy Logic
	if is_sprinting and velocity.length() > 0.1:
		current_energy = max(0.0, current_energy - energy_depletion_rate * delta)
		if current_energy <= 0.0:
			is_exhausted = true
	else:
		current_energy = min(max_energy, current_energy + energy_restoration_rate * delta)
		# Recover from exhaustion once we have enough energy (e.g. 20%)
		if is_exhausted and current_energy >= max_energy * 0.2:
			is_exhausted = false
	
	# Take damage if starving or dehydrated
	if current_hunger <= 0.0 or current_thirst <= 0.0:
		current_health = max(0.0, current_health - 2.0 * delta)
		
	if current_health <= 0.0 and not is_dead:
		die()

	# Emit signal for HUD
	stats_updated.emit(current_health, current_hunger, current_thirst, current_sanity, current_energy)

func start_driving(vehicle):
	is_driving = true
	current_vehicle = vehicle
	
	# Disable local physics/collisions
	$CollisionShape3D.disabled = true
	visible = true # Keep player visible so we can see them driving
	
	# Disable player camera (vehicle will provide its own)
	var p_cam = cam_vertical.get_node_or_null("Camera3D")
	if p_cam: p_cam.current = false
	
	# REPARENT to vehicle for perfect sync
	# We store the transform, move the node, then restore the transform in local space
	var old_parent = get_parent()
	if old_parent:
		old_parent.remove_child(self)
	vehicle.add_child(self)
	
	# Position player in the driver's area (local to car)
	position = Vector3(0, 0.4, 0.5) 
	rotation = Vector3(0, PI, 0) # Flipped 180 degrees
	if armature:
		armature.rotation = Vector3.ZERO 
	
	# Reset camera base so it doesn't carry over walking rotation
	if cam_horizontal:
		cam_horizontal.rotation = Vector3.ZERO
	
	animation_player.play("Driving")

func exit_vehicle():
	if not current_vehicle: return
	
	is_driving = false
	var vehicle_node = current_vehicle
	
	# Calculate world exit pos before removing child
	var exit_pos = vehicle_node.global_position + vehicle_node.global_transform.basis.x * 2.2 + Vector3.UP * 0.5
	
	# REPARENT back to world
	vehicle_node.remove_child(self)
	vehicle_node.get_parent().add_child(self)
	global_position = exit_pos
	global_rotation.y = vehicle_node.global_rotation.y
	if armature:
		armature.rotation = Vector3.ZERO
	
	# Re-enable player physics and camera
	$CollisionShape3D.disabled = false
	visible = true
	
	var p_cam = cam_vertical.get_node_or_null("Camera3D")
	if p_cam: p_cam.current = true
	
	vehicle_node.exit_vehicle()
	current_vehicle = null
	
	animation_player.play("Idle")

func _on_animation_finished(anim_name: String):
	if anim_name == "Roll":
		is_rolling = false

func die():
	is_dead = true
	animation_player.play("Death01")

func update_animations(input_dir: Vector2) -> void:
	if is_dead:
		return
		
	if is_rolling:
		return

	if is_on_floor():
		if not was_on_floor:
			animation_player.play("Jump_Land", 0.1)
		
		if input_dir.length() == 0:
			if animation_player.current_animation == "Jump_Land" and animation_player.is_playing():
				return
			if animation_player.current_animation == "Jump_Start" and animation_player.is_playing():
				return

		if input_dir.length() > 0:
			if is_crouching:
				animation_player.play("Crouch_Fwd", 0.2)
			elif is_sprinting:
				animation_player.play("Sprint", 0.3)
			else:
				animation_player.play("Walk", 0.3)
		else:
			animation_player.play("Crouch_Idle" if is_crouching else "Idle", 0.2)
	else:
		# Mid-air logic
		if animation_player.current_animation != "Jump_Start":
			animation_player.play("Jump", 0.3)
		elif not animation_player.is_playing():
			animation_player.play("Jump", 0.3)

func toggle_build_mode():
	is_building = !is_building
	print("Build mode toggled. is_building: ", is_building)
	if hud_instance:
		hud_instance.set_build_mode(is_building)
		
	if is_building:
		building_system.activate(self)
	else:
		if is_flying: toggle_fly_mode()
		building_system.deactivate()

func toggle_fly_mode():
	is_flying = !is_flying
	print("Fly mode toggled. is_flying: ", is_flying)
	if is_flying:
		fly_cam.global_transform = camera.global_transform
		fly_cam.make_current()
	else:
		camera.make_current()

func _process_fly_mode(delta):
	var input_dir = Input.get_vector("player_left", "player_right", "player_forward", "player_backward")
	var up_down = Input.get_axis("fly_down", "fly_up")
	
	# Get flattened camera vectors
	var basis = fly_cam.global_transform.basis
	var forward = -basis.z
	forward.y = 0
	
	if forward.length() < 0.1:
		# If looking straight up/down, use the camera's UP vector projected on ground
		forward = -basis.y if basis.z.y > 0 else basis.y
		forward.y = 0
		
	forward = forward.normalized()
	
	var right = basis.x
	right.y = 0
	right = right.normalized()
	
	# Calculate move direction
	var move_dir = (forward * -input_dir.y + right * input_dir.x).normalized()
	
	# Compute next position
	var velocity_vec = move_dir * fly_speed
	velocity_vec.y = up_down * fly_speed # Vertical movement is absolute
	
	if not is_instance_valid(fly_cam): return
	var next_pos = fly_cam.global_position + velocity_vec * delta
	
	# Restriction to Territory (Square)
	if has_territory:
		var territories = get_tree().get_nodes_in_group("territory")
		if territories.size() > 0:
			var t = territories[0]
			if is_instance_valid(t):
				var half_size = 20.0 # Match territory half-size
				var dx = next_pos.x - t.global_position.x
				var dz = next_pos.z - t.global_position.z
				
				next_pos.x = t.global_position.x + clamp(dx, -half_size, half_size)
				next_pos.z = t.global_position.z + clamp(dz, -half_size, half_size)
	
	fly_cam.global_position = next_pos
