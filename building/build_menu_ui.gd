extends Control

const BuildBlueprint = preload("res://building/blueprint.gd")

signal blueprint_selected(blueprint: BuildBlueprint)

@onready var main_vbox = %MainVBox
@onready var search_bar = %SearchBar
@onready var category_tabs = %CategoryTabs
@onready var sub_category_tabs = %SubCategoryTabs

var all_blueprints: Array[BuildBlueprint] = []

func _ready():
	_load_blueprints()
	category_tabs.tab_changed.connect(_on_category_tabs_tab_changed)
	sub_category_tabs.tab_changed.connect(_on_sub_category_tabs_tab_changed)
	search_bar.text_changed.connect(_on_search_bar_text_changed)
	_on_category_tabs_tab_changed(0) # Initialize

func _load_blueprints():
	all_blueprints.clear()
	var path = "res://building/blueprints/"
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tres"):
				var res = load(path + file_name)
				if res is BuildBlueprint:
					all_blueprints.append(res)
			file_name = dir.get_next()

func _update_grid():
	# Clear existing sections
	for child in main_vbox.get_children():
		child.queue_free()
	
	# 1. NORMALIZE STRINGS (Fix Plural/Singular mismatch)
	var category = category_tabs.get_tab_title(category_tabs.current_tab).strip_edges().to_lower().replace("s", "")
	var sub_category = sub_category_tabs.get_tab_title(sub_category_tabs.current_tab).strip_edges().to_lower().replace("s", "")
	var search_text = search_bar.text.to_lower()
	
	# Grouping by "Material"
	var groups = {} 
	
	for blueprint in all_blueprints:
		var bp_cat = blueprint.category.to_lower().replace("s", "")
		var bp_sub = blueprint.sub_category.to_lower().replace("s", "")
		
		if bp_cat == category and bp_sub == sub_category:
			if search_text == "" or search_text in blueprint.name.to_lower():
				# Detect Material
				var mat_name = "OTHER"
				var full_text = (blueprint.name + " " + blueprint.description).to_upper()
				if "WOOD" in full_text: mat_name = "WOOD"
				elif "STONE" in full_text: mat_name = "STONE"
				elif "MARBLE" in full_text: mat_name = "MARBLE"
				elif "METAL" in full_text: mat_name = "METAL"
				
				if not groups.has(mat_name): groups[mat_name] = []
				groups[mat_name].append(blueprint)
	
	# Create sections (Sorted: Wood first, then alpha)
	var g_keys = groups.keys()
	g_keys.sort()
	
	for g_name in g_keys:
		_create_section(g_name + " " + sub_category.to_upper() + "S", groups[g_name])

func _create_section(title: String, blueprints: Array):
	var section_vbox = VBoxContainer.new()
	section_vbox.add_theme_constant_override("separation", 15)
	
	# Header HBox
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	
	var indicator = ColorRect.new()
	indicator.custom_minimum_size = Vector2(4, 20)
	indicator.color = Color(0, 0.8, 1, 1) # Cyan accent
	hbox.add_child(indicator)
	
	var label = Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	hbox.add_child(label)
	
	# Divider Line
	var line = ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = SIZE_EXPAND_FILL
	line.size_flags_vertical = SIZE_SHRINK_CENTER
	line.color = Color(1, 1, 1, 0.1)
	hbox.add_child(line)
	
	section_vbox.add_child(hbox)
	
	# Grid
	var grid = GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	
	for bp in blueprints:
		_create_item_button(bp, grid)
	
	section_vbox.add_child(grid)
	main_vbox.add_child(section_vbox)

func _create_item_button(blueprint: BuildBlueprint, parent: GridContainer):
	var container = PanelContainer.new()
	container.custom_minimum_size = Vector2(100, 115) # Taller for text
	
	# Modern Item Styling
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.05)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	container.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	container.add_child(vbox)
	
	# Icon Holder
	var icon_parent = Control.new()
	icon_parent.custom_minimum_size = Vector2(80, 80)
	icon_parent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(icon_parent)
	
	var icon = TextureRect.new()
	icon.texture = blueprint.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(65, 65)
	icon.layout_mode = 1
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	icon_parent.add_child(icon)
	
	# Name Label
	var label = Label.new()
	label.text = blueprint.name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 10) # SMALL
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6)) # Subtle
	label.custom_minimum_size = Vector2(80, 20)
	vbox.add_child(label)
	
	var btn = Button.new()
	btn.flat = true
	btn.layout_mode = 1
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.tooltip_text = (blueprint.name + "\n" + blueprint.description).strip_edges()
	container.add_child(btn)
	
	# Hover Effect
	btn.mouse_entered.connect(func(): style.bg_color = Color(0, 0.8, 1, 0.2); style.border_color = Color(0, 0.8, 1, 0.6); label.add_theme_color_override("font_color", Color(1, 1, 1, 1)))
	btn.mouse_exited.connect(func(): style.bg_color = Color(1, 1, 1, 0.05); style.border_color = Color(1, 1, 1, 0.1); label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6)))
	btn.pressed.connect(func(): blueprint_selected.emit(blueprint))
	
	parent.add_child(container)

func open():
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close():
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_category_tabs_tab_changed(_tab):
	var category = category_tabs.get_tab_title(_tab).strip_edges().capitalize()
	
	# Update Sub-Categories based on your request
	sub_category_tabs.clear_tabs()
	var subs = []
	match category.to_upper():
		"STRUCTURES":
			subs = ["Recent", "Foundations", "Wall", "Ceiling", "Roof", "Stairs", "Doors", "Column"]
		"FACILITIES":
			subs = ["Recent", "Crafting Processes", "Gathering and Productions", "Storage", "Power Generations", "Garage"]
		"FURNITURE":
			subs = ["Recent", "Bed", "Lighting", "Tables", "Floor Furniture", "Wall Furniture", "Floor Decor", "Wall Decor", "Entertainment", "Collectible Trophy"]
		_:
			subs = ["Recent", "All"]
			
	for s in subs:
		sub_category_tabs.add_tab(s)
	
	_update_grid()

func _on_sub_category_tabs_tab_changed(_tab):
	_update_grid()

func _on_search_bar_text_changed(_new_text):
	_update_grid()
