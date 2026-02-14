extends CanvasLayer

const BuildBlueprint = preload("res://building/blueprint.gd")

@onready var health_bar = %HealthBar
@onready var hunger_bar = %HungerBar
@onready var thirst_bar = %ThirstBar
@onready var sanity_bar = %SanityBar
@onready var energy_bar = %EnergyBar

@onready var emote_wheel = %EmoteWheel
@onready var emote_container = %EmoteContainer
@onready var selection_pointer = %SelectionPointer

var emotes = ["Roll", "Attack", "Wave", "Dance", "Point", "Sit", "Clap", "Laugh"]
var selected_emote_index = -1
var player_ref: CharacterBody3D

@onready var interact_info = %InteractInfo
@onready var interact_icon = %InteractIcon
@onready var interact_name = %InteractName
@onready var nearby_list = %NearbyList

func setup(player: CharacterBody3D):
	player_ref = player
	if player.has_signal("stats_updated"):
		player.stats_updated.connect(_on_player_stats_updated)
	
	_update_ui(player.current_health, player.current_hunger, player.current_thirst, player.current_sanity, player.current_energy)
	_setup_emote_wheel()
	
	# Setup Inventories
	if player.inventory_data:
		%QuickAccessBar.setup(player.inventory_data)
		%MainInventory.setup(player.inventory_data)
	
	%BuildMenuUI.blueprint_selected.connect(_on_blueprint_selected)

func _on_blueprint_selected(blueprint: BuildBlueprint):
	if player_ref:
		player_ref.building_system.select_blueprint(blueprint)
		player_ref.building_system.is_menu_open = false
		%BuildMenuUI.close()

func toggle_build_menu():
	if %BuildMenuUI.visible:
		%BuildMenuUI.close()
		if player_ref and player_ref.is_building:
			%BuildHUD.visible = true
			if player_ref.building_system: player_ref.building_system.is_menu_open = false
	else:
		%BuildMenuUI.open()
		%BuildHUD.visible = false
		if player_ref and player_ref.building_system: player_ref.building_system.is_menu_open = true

func update_interact_info(target):
	if target == null:
		interact_info.visible = false
		return
	
	interact_info.visible = true
	
	if target.has_method("enter_vehicle"):
		interact_name.text = target.name
		interact_icon.texture = null # Could adds a vehicle icon later
	elif "item_data" in target:
		interact_name.text = target.item_data.item_name
		interact_icon.texture = target.item_data.icon
	elif target.has_meta("blueprint_name"):
		interact_name.text = target.get_meta("blueprint_name")
		interact_icon.texture = null
	elif target.has_method("get_interact_text"):
		interact_name.text = target.name # Fallback to node name if it has interaction
		interact_icon.texture = null
	else:
		interact_name.text = "Object"
		interact_icon.texture = null

func update_nearby_items(items: Array):
	# Clear existing
	for child in nearby_list.get_children():
		child.queue_free()
	
	for item in items:
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		hbox.alignment = BoxContainer.ALIGNMENT_END
		
		var label = Label.new()
		if "item_data" in item:
			label.text = item.item_data.item_name
		elif item.has_meta("blueprint_name"):
			label.text = item.get_meta("blueprint_name")
		else:
			label.text = item.name
		label.add_theme_font_size_override("font_size", 12)
		hbox.add_child(label)
		
		var icon = TextureRect.new()
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if "item_data" in item:
			icon.texture = item.item_data.icon
		hbox.add_child(icon)
		
		nearby_list.add_child(hbox)

func toggle_inventory():
	var is_visible = !%MainInventory.visible
	%MainInventory.visible = is_visible
	
	if is_visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _setup_emote_wheel():
	# Clear container
	for child in emote_container.get_children():
		child.queue_free()
	
	var radius = 140.0
	var angle_step = (PI * 2.0) / emotes.size()
	
	for i in range(emotes.size()):
		var label = Label.new()
		label.text = emotes[i]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		
		# Position on circle
		var angle = i * angle_step - PI/2
		var pos = Vector2(cos(angle), sin(angle)) * radius
		
		label.position = pos + Vector2(200, 200) - Vector2(50, 15) # Offset to center label
		label.custom_minimum_size = Vector2(100, 30)
		
		emote_container.add_child(label)

func _process(_delta):
	if emote_wheel.visible:
		_handle_wheel_selection()

func _handle_wheel_selection():
	var center = emote_wheel.global_position + emote_wheel.size / 2
	var mouse_pos = get_viewport().get_mouse_position()
	var dir = (mouse_pos - center).normalized()
	
	if (mouse_pos - center).length() > 20: # Deadzone
		var angle = atan2(dir.y, dir.x) + PI/2
		if angle < 0: angle += PI * 2
		
		selection_pointer.rotation = angle - PI/2
		
		var angle_step = (PI * 2.0) / emotes.size()
		# Offset angle to center selection on segments
		var adjusted_angle = angle + angle_step / 2.0
		if adjusted_angle > PI * 2: adjusted_angle -= PI * 2
		
		selected_emote_index = int(adjusted_angle / angle_step) % emotes.size()
		
		# Highlight selection
		for i in range(emote_container.get_child_count()):
			var label = emote_container.get_child(i)
			if i == selected_emote_index:
				label.add_theme_color_override("font_color", Color(0, 0.8, 1))
				label.scale = Vector2(1.2, 1.2)
			else:
				label.remove_theme_color_override("font_color")
				label.scale = Vector2(1.0, 1.0)
	else:
		selected_emote_index = -1

func set_emote_wheel_visible(is_visible: bool):
	emote_wheel.visible = is_visible
	if is_visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if selected_emote_index != -1:
			_trigger_emote(emotes[selected_emote_index])

func _trigger_emote(emote_name: String):
	print("Triggering Emote: ", emote_name)
	# Check if player has the animation
	var anim_name = ""
	match emote_name:
		"Roll": anim_name = "Roll_RM"
		"Attack": anim_name = "Sword_Attack_RM"
		# Add more mappings as needed
	
	if anim_name != "" and player_ref.animation_player.has_animation(anim_name):
		player_ref.animation_player.play(anim_name)

func set_build_mode(active: bool):
	%BuildHUD.visible = active
	# Hide/Show other HUD elements to focus on building
	%MarginContainer.visible = !active # Survival bars
	%QuickAccessBar.visible = !active
	%NearbyContainer.visible = !active
	%InteractInfo.visible = !active if active else %InteractInfo.visible
	# You can add more logic here to update icons/states within BuildHUD

func _on_player_stats_updated(health, hunger, thirst, sanity, energy):
	_update_ui(health, hunger, thirst, sanity, energy)

func _update_ui(health, hunger, thirst, sanity, energy):
	health_bar.value = health
	hunger_bar.value = hunger
	thirst_bar.value = thirst
	sanity_bar.value = sanity
	energy_bar.value = energy
