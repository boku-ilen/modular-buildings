extends Node3D
class_name BuildingFactory


const hinge_material: ShaderMaterial = preload("res://Elements/hinge_corner.tres")
const hinge_corner_script: Script = preload("res://Elements/hinge-corner.gd")

# How much the building blocks may be scaled before using spacers
const MIN_SCALE := 0.9
const MAX_SCALE := 1.1
# How much deviation from 90 deg is allowed before using hinge-corner
const TOLERATE_90_DEG_DEVIATION = 0.01

## Build a building from footprint, floors and asset pack definition
##  footprint: Array[Vector2]
##  asset_pack: Dictionary[int:Array[AssetEntry]] mapping floor index (0 = ground) to possible assets
##  floors: total number of floors (height)
##  floor_height: vertical distance between floors (in metres)
static func build_building(building_root: Node3D, metadata: BuildingMetadata) -> Node3D:
	# Long term it should probably be deterministic
	randomize()
	
	var edges: Array[Edge] = _footprint_to_edges(metadata.footprint)
	building_root.position = metadata.position
	if edges.is_empty(): 
		return building_root
	
	var module_indices := {}
	var overall_floor_height := 0.
	
	var corner_infos = _compute_corner_infos(edges)
	
	# Iterate floors and edges
	for floor_num in metadata.floor_definitions.size():
		# Node hierarchy for current floor
		var floor_root = Node3D.new()
		floor_root.name = "floor#%d" % floor_num
		building_root.add_child(floor_root)
		
		# Meta
		var floor_assets = metadata.floor_definitions[floor_num]
		var floor_height = floor_assets.height
		
		# Create the corner pieces, the edges will be updated according to they
		# mesh extent (to guarantee no overlap)
		for i in edges.size():
			var edge_current = _populate_corner(
				floor_root,
				edges[i], 
				floor_assets.corner_90, 
				corner_infos[i],
				overall_floor_height)
			var edge_root = Node3D.new()
			edge_root.name = "edge#%d" % i
			floor_root.add_child(edge_root)
			
			# Populate the edges with modules
			# To ensure a uniform distribution along the floors, store the indices of the same
			# floor asset packs
			module_indices = _compute_edges(
				edge_root, 
				edge_current.p0,
				edge_current.p1, 
				overall_floor_height, 
				floor_assets.walls, 
				floor_assets.spacer_block,
				module_indices)
		
		overall_floor_height += floor_height
	
	return building_root

# Returns the new edge with regard to the corner
static func _populate_corner(
	root: Node3D,
	edge_i: Edge,
	corner_mesh: Mesh, 
	corner_info_i: Dictionary,
	overall_floor_height: float) -> Edge:
	# Create a hinge corner asset from the mesh
	var hinge_corner_instance := MeshInstance3D.new()
	hinge_corner_instance.mesh = corner_mesh
	
	# Write the standard material textures/etc. to the hinge-corner asset
	for idx in hinge_corner_instance.mesh.get_surface_count():
		var standard_mat = hinge_corner_instance.mesh.surface_get_material(idx)
		var shader_mat: ShaderMaterial = hinge_material.duplicate(true)
		
		if standard_mat != null:
			standard_mat = standard_mat.duplicate()
			utility.copy_standard_to_shader(standard_mat, shader_mat)
		
		hinge_corner_instance.mesh.surface_set_material(idx, shader_mat)
	
	# Add a script to the meshinstance
	hinge_corner_instance.mesh = hinge_corner_instance.mesh.duplicate(true)
	hinge_corner_instance.set_script(hinge_corner_script)
	
	# Cached asset extents
	var asset_extent = ModuleSpecs.get_module_spec(corner_mesh).asset_extent
	
	# Create a new edge that respects the extent of the corner asset
	var subtrahend_0 = edge_i.dir * asset_extent.x 
	var subtrahend_1 = edge_i.dir * asset_extent.y
	
	root.add_child(hinge_corner_instance)
	hinge_corner_instance.angle = corner_info_i["angle"]
	hinge_corner_instance.position = corner_info_i["position"]
	hinge_corner_instance.look_at(
		corner_info_i.position + Vector3(corner_info_i.direction.x, 0, corner_info_i.direction.y) * 5
	)
	hinge_corner_instance.position += Vector3.UP * overall_floor_height
	
	# Kind of arbitrary right now, might want to rework this (technical debt)
	var adjustment_angle = 45 if corner_info_i["angle"] < PI else 225
	hinge_corner_instance.rotate(Vector3.UP, deg_to_rad(adjustment_angle))
	
	return Edge.new(edge_i.p0 + subtrahend_0, edge_i.p1 - subtrahend_1)


static func _compute_corner_infos(edges: Array[Edge]) -> Array[Dictionary]:
	var corner_infos: Array[Dictionary] = []
	corner_infos.resize(edges.size())
	for i in edges.size():
		# Set dict
		corner_infos[i] = {}
		
		# Determine the angle to the next edge 
		var edge_current: Edge = edges[i]
		var edge_next: Edge = edges[(i+1) % edges.size()]
		corner_infos[i]["angle"] = rad_to_deg((edge_current.dir).angle_to(edge_next.dir))
		
		# Correct transformation (position and rotation)
		var corner_position = edge_current.p1
		corner_infos[i]["position"] = Vector3(corner_position.x, 0, corner_position.y)
		# Rather arbitrarily (technical debt) rotation has to be applied, 
		# we might fix this and export the corners more adequately
		corner_infos[i]["direction"] = (edge_current.dir - edge_next.dir)
		
	return corner_infos


## Populate a single edge with facade modules
static func _instance_module(parent: Node3D, mesh: Mesh, module_width: float, scale_x: float,
		p1: Vector2, dir: Vector2, cursor: float, overall_floor_height: float, edge_vec: Vector2, index: int) -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.name = "wall_element#%d" % [index]
	inst.scale.x *= scale_x

	# Position centre‑line of segment along edge
	var off: Vector2 = dir * (cursor + module_width * scale_x * 0.5)
	inst.position = Vector3(p1.x + off.x, overall_floor_height, p1.y + off.y)

	# Aim outward (perpendicular to edge)
	var look_dir = Vector3(edge_vec.x, overall_floor_height, edge_vec.y).cross(Vector3.UP)
	inst.look_at_from_position(inst.position, inst.position + look_dir)

	parent.add_child(inst)


# ------------------------------------------------
# _populate_edge with balanced spacers
# ------------------------------------------------
static func _compute_edges(parent: Node3D, p1: Vector2, p2: Vector2,
		overall_floor_height: float, floor_assets: Array, spacer_block: Mesh, module_indices: Dictionary) -> Dictionary:
	var edge_vec: Vector2 = p2 - p1
	var edge_length: float = edge_vec.length()
	if edge_length < 0.01:
		return module_indices
	var dir: Vector2 = edge_vec.normalized()

	var spacer_width: float = spacer_block.get_aabb().size.x

	# ------------------------
	# 1) Choose main modules   
	# ------------------------
	# We need to store the modules until we know how many of them can fit
	var modules: Array = []
	
	# To ensure a uniform distribution along the floors, store the indices
	var module_indices_set = floor_assets in module_indices
	var current_block_index := 0
	
	# Store how much width we processed altogether until now
	var used_width := 0.0
	
	var use_fillers := false
	var spacers := {"left": [], "right": [], "scale": 1.}
	var module_scale := 1.0
	while not floor_assets.is_empty():
		var random_index: int
		# Not set until first floor has been processed
		if not module_indices_set:
			if not floor_assets in module_indices:
				module_indices[floor_assets] = []
			random_index = randi() % floor_assets.size()
			module_indices[floor_assets].append(random_index)
		else:
			# We have to use modulo because if the modules of each floor are not uniformly sized,
			# the current_block_index may be bigger than in the module_indices defined in the first
			# iteration.
			# TODO: Think about a smarter way too approach this
			random_index = module_indices[floor_assets][current_block_index % module_indices[floor_assets].size()]
		
		var mesh: Mesh = floor_assets[random_index]
		
		# FIXME: properly handle this case which may well occur depending on alternating
		# floor definitions (e.g. 1st floor 3 assets, 2nd floor 5 assets)
		if mesh == null:
			print("MESH WAS NULL!")
			break
		
		var module_width := mesh.get_aabb().size.x
		# In case no more module fits, decide wether scaling is an option or to use spacers 
		if used_width + module_width > edge_length:
			module_scale = (edge_length / (used_width + module_width))
			
			if module_scale < MIN_SCALE or module_scale > MAX_SCALE:
				module_scale = 1.0
				use_fillers = true
				break
			
			module_scale = (edge_length / used_width) if not module_scale < 1.0 else module_scale
			modules.append({"mesh": mesh, "width": module_width})
			used_width += module_width
			current_block_index += 1
			break
			
		modules.append({"mesh": mesh, "width": module_width})
		used_width += module_width
		current_block_index += 1

	if use_fillers:
		spacers = _get_spacers(edge_length, used_width, spacer_width)

	# ------------------------
	# 2) Instantiate modules   
	# ------------------------
	var cursor := 0.0

	# 2a) Leading spacers
	for i in spacers["left"]:
		_instance_module(parent, spacer_block, spacer_width, spacers["scale"],
			p1, dir, cursor, overall_floor_height, edge_vec, i)
		cursor += spacer_width * spacers["scale"]

	# 2b) Main building modules
	var index := 0
	for m in modules:
		_instance_module(parent, m["mesh"], m["width"], module_scale,
			p1, dir, cursor, overall_floor_height, edge_vec, index)
		cursor += m.width * module_scale
		index += 1

	# 2c) Trailing spacers
	for i in spacers["right"]:
		_instance_module(parent, spacer_block, spacer_width, spacers["scale"],
			p1, dir, cursor, overall_floor_height, edge_vec, i)
		cursor += spacer_width * spacers["scale"]
	
	return module_indices


static func _get_spacers(edge_length: float, used_width: float, spacer_width: float):
	assert(spacer_width != 0.0, "Not a valid spacer-element")
	
	var remaining_edge = max(edge_length - used_width, 0.0)
	var spacer_count = round(remaining_edge / spacer_width)
	
	if remaining_edge == 0.0:
		return {"left": 0, "right": 0, "scale": 1.0}
	var spacer_scale = remaining_edge / (spacer_count * spacer_width)
	
	var left := int(spacer_count / 2)
	var right := int(spacer_count - left)
	return {"left": left, "right": right, "scale": spacer_scale}


static func _footprint_to_edges(footprint: Array[Vector2]) -> Array[Edge]:
	if Geometry2D.is_polygon_clockwise(footprint): 
		footprint.reverse()
	
	if footprint.size() < 3:
		push_error("Footprint must have at least 3 vertices")
		return []
	
	# Create edge list
	var edges: Array[Edge] = []
	for i in range(footprint.size()):
		edges.push_back(Edge.new(footprint[i], footprint[(i+1)%footprint.size()]))
	
	return edges
