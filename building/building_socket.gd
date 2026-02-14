@tool
extends Marker3D

func _ready():
	if not Engine.is_editor_hint():
		return
		
	# Clear existing children to avoid duplicates on script reload
	for child in get_children():
		if child.name == "_EditorVisual":
			child.free()
			
	var vis = Node3D.new()
	vis.name = "_EditorVisual"
	add_child(vis)
	
	var mesh_inst = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.08
	mesh.height = 0.4
	mesh_inst.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	
	# Color code by socket type
	var type = get_meta("type") if has_meta("type") else "unknown"
	match type:
		"foundation": mat.albedo_color = Color(0, 0.8, 1) # Cyan
		"wall": mat.albedo_color = Color(1, 0.6, 0) # Orange
		"roof": mat.albedo_color = Color(0.8, 0, 1) # Purple
		_: mat.albedo_color = Color(1, 1, 1) # White
		
	mesh_inst.material_override = mat
	
	# Rotate to point along -Z (Forward)
	mesh_inst.rotation.x = -PI/2 
	mesh_inst.position.z = -0.2
	vis.add_child(mesh_inst)
	
	# Add a small base sphere
	var base_inst = MeshInstance3D.new()
	var base_mesh = SphereMesh.new()
	base_mesh.radius = 0.1
	base_mesh.height = 0.2
	base_inst.mesh = base_mesh
	base_inst.material_override = mat
	vis.add_child(base_inst)
