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
	
	var edges: Array[Edge] = _prepare_building(building_root, metadata)
	if edges.is_empty(): 
		return building_root
	
	var module_indices := {}
	var overall_floor_height := 0.
	
	# Iterate floors and edges
	for floor_num in metadata.floor_definitions.size():
		var floor_root = Node3D.new()
		floor_root.name = "floor#%d" % floor_num
		building_root.add_child(floor_root)
		var floor_assets = metadata.floor_definitions
		var floor_height = floor_assets[floor_num].height
		
		# Create the corner pieces, the edges will be updated according to the
		# mesh extent (to guarantee no overlap)
		var updated_edges = _populate_corners(
			floor_root, 
			edges, 
			floor_assets[floor_num].corner_90, 
			floor_assets[floor_num].corner_270, 
			overall_floor_height)
		
		var i = 0
		for edge_current in updated_edges:
			var edge_root = Node3D.new()
			edge_root.name = "edge#%d" % i
			floor_root.add_child(edge_root)
			
			# Populate the edges with modules
			# To ensure a uniform distribution along the floors, store the indices of the same
			# floor asset packs
			module_indices = _populate_edge(
				edge_root, 
				edge_current.p0,
				edge_current.p1, 
				overall_floor_height, 
				floor_assets[floor_num].walls, 
				floor_assets[floor_num].spacer_block,
				module_indices)
			
			i += 1
		
		overall_floor_height += floor_height
	
	return building_root


static func _populate_corners(parent: Node3D, edges: Array[Edge], corner: Mesh, corner_270: Mesh, overall_floor_height: float) -> Array[Edge]:
	var i = 0
	var new_edges: Array[Edge] = []
	var corner_instance := MeshInstance3D.new()
	corner_instance.mesh = corner
	var corner_270_instance := MeshInstance3D.new()
	corner_270_instance.mesh = corner_270
	
	# For the hinge, we overwrite the mesh to be able to apply a new material
	var hinge_corner_instance := MeshInstance3D.new()
	hinge_corner_instance.mesh = corner
	
	var prepare_hinge_mesh = func(mesh: Mesh, idx: int):
		var standard_mat = mesh.surface_get_material(idx)
		var shader_mat: ShaderMaterial = hinge_material.duplicate(true)
		
		if standard_mat != null:
			standard_mat = standard_mat.duplicate()
			utility.copy_standard_to_shader(standard_mat, shader_mat)
		
		mesh.surface_set_material(idx, shader_mat)
	
	var prepare_hinge_node = func(node: MeshInstance3D):
		node.mesh = node.mesh.duplicate(true)
		node.set_script(hinge_corner_script)
	
	for surface_idx in hinge_corner_instance.mesh.get_surface_count():
		prepare_hinge_mesh.call(hinge_corner_instance.mesh, surface_idx)
	prepare_hinge_node.call(hinge_corner_instance)
	
	# Store overall current angle for computing accurate new edge positions in consideration
	# of the new corner assets.
	# Consider that starting non-x-aligned requires to already have an angle
	var start_angle := Vector2(1, 0).angle_to(edges[0].p1 - edges[0].p0)
	var overall_angle := start_angle
	# Store the previous asset so we can properly subtract it from the following edge
	var previous_asset_extent := Vector2.ZERO
	var is_90_deg := false
	var is_270_deg := false
	for edge_current in edges:
		# Determine the angle to the next edge to decide whether we implicitly (hinge-asset) or
		# explicitly (90° fixed asset) create the object at that corner
		var edge_next: Edge = edges[(i+1) % edges.size()]
		var angle_to_next = (edge_current.dir).angle_to(edge_next.dir)
		
		is_90_deg = angle_to_next > PI / 2 - (PI / 2) * TOLERATE_90_DEG_DEVIATION and angle_to_next < PI / 2 + (PI / 2) * TOLERATE_90_DEG_DEVIATION
		is_270_deg = angle_to_next < -(PI / 2 - (PI / 2) * TOLERATE_90_DEG_DEVIATION) and angle_to_next > -(PI / 2 + (PI / 2) * TOLERATE_90_DEG_DEVIATION)

		var explicit_instance = corner_instance if is_90_deg else null
		explicit_instance = corner_270_instance if is_270_deg else explicit_instance
		
		# An explicit corner is a mesh created for that type of building
		if is_90_deg or is_270_deg:
			var explicit_corner = explicit_instance.duplicate(7) as Node3D
			
			# In a later step, we create new edges that respect the corner assets;
			# for that we use the AABB of the asset (apply transforms before export!).
			# Because some assets might have an extend into negative coords on x/z-plane,
			# we need to respect that overhang such that there are no gaps when filling 
			# the walls. We swap sides (z -> x ...) because the corner is 90° from the new edge
			# y▲                                     
			# ┤│   ┬ ... wall element y<0                           
			# ┤│   ┤ ... wall elment x<0                                              
			# ┤│   @ ... coordinate system origin
			# ┤@─────────►                           
			# ┬┬┬┬┬┬┬┬┬┬ x                           
			var aabb = utility.get_combined_aabb(explicit_instance)
			var overhang_z_side =  (aabb.size - aabb.end).x
			var overhang_x_side = (-aabb.size - aabb.position).z if is_90_deg else -(aabb.size - aabb.end).z 
			var asset_extent = Vector2(aabb.size.z - overhang_z_side, aabb.size.x + overhang_x_side)
			
			# Correct transformation (position and rotation)
			var look_dir = Vector3(
				(edge_current.p1 - edge_current.p0).x, 
				overall_floor_height, 
				(edge_current.p1 - edge_current.p0).y
			).cross(Vector3.UP)
			
			explicit_corner.look_at_from_position(explicit_corner.position, (explicit_corner.position + look_dir))
			var corner_position = edge_current.p1
			explicit_corner.position = Vector3(corner_position.x, overall_floor_height, corner_position.y)
			parent.add_child(explicit_corner)
			
			# Create a new edge that respects the extent of the corner asset
			var subtrahend_0 = Vector2(previous_asset_extent.x, 0)
			var subtrahend_1 = Vector2(asset_extent.y, 0)
			var new_edge_0 = edge_current.p0 + subtrahend_0.rotated(overall_angle)
			var new_edge_1 = edge_current.p1 - subtrahend_1.rotated(overall_angle)
			
			new_edges.append([new_edge_0, new_edge_1])
			
			previous_asset_extent = asset_extent
			
		# An implicit corner is for dull corners (the scene should behave like a hinge)
		else:
			var hinge_corner = hinge_corner_instance.duplicate(7)
			parent.add_child(hinge_corner)
			hinge_corner.angle = rad_to_deg(angle_to_next)
			
			# Correct transformation (position and rotation)
			var corner_position = edge_current.p1
			hinge_corner.position = Vector3(corner_position.x, overall_floor_height, corner_position.y)
			
			var aabb = utility.get_combined_aabb(hinge_corner)
			var overhang_z_side =  (aabb.size - aabb.end).x
			var overhang_x_side = (-aabb.size - aabb.position).z
			var asset_extent = Vector2(aabb.size.z - overhang_z_side, aabb.size.x + overhang_x_side)
			
			# Create a new edge that respects the extent of the corner asset
			var subtrahend_0 = edge_current.dir * asset_extent.x 
			var subtrahend_1 = edge_current.dir * asset_extent.y
			var new_edge_0 = edge_current.p0 + subtrahend_0
			var new_edge_1 = edge_current.p1 - subtrahend_1
			
			new_edges.append(Edge.new(new_edge_0, new_edge_1))
			
			# find the edge between the current end-point and the next start-point 
			var direction_next = edge_next.dir
			var subtrahend_0_next = direction_next * asset_extent.x 
			var new_edge_next = edge_next.p0 + subtrahend_0_next
			
			var look_dir = Vector3(new_edge_1[0], overall_floor_height, new_edge_1[1]).direction_to(Vector3(new_edge_next.x, overall_floor_height, new_edge_next.y))
			look_dir = look_dir.cross(Vector3.UP)
			hinge_corner.look_at(hinge_corner.position - look_dir)
			# Rather arbitrary, but corners are exported optimally for when they are *not* hinges
			# which makes this adjustment necessary
			hinge_corner.rotation_degrees.y -= 135
			
			previous_asset_extent = asset_extent
		
		i += 1
		overall_angle += angle_to_next
	
	# Finally also apply the last asset to the first edge (was not set in first iteration)
	if is_90_deg or is_270_deg:
		new_edges[0].p0 += Vector2(previous_asset_extent.x, 0).rotated(start_angle)
	
	return new_edges


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
static func _populate_edge(parent: Node3D, p1: Vector2, p2: Vector2,
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


static func _prepare_building(building_root: Node3D, metadata: BuildingMetadata) -> Array[Edge]:
	var footprint = metadata.footprint 
	if Geometry2D.is_polygon_clockwise(footprint): 
		footprint.reverse()
	
	building_root.position = metadata.position
	if footprint.size() < 3:
		push_error("Footprint must have at least 3 vertices")
		return []
	
	# Create edge list
	var edges: Array[Edge] = []
	for i in range(footprint.size()):
		edges.push_back(Edge.new(footprint[i], footprint[(i+1)%footprint.size()]))
	
	return edges
