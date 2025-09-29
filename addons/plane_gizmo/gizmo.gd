extends EditorNode3DGizmoPlugin
class_name FlatGizmoPlugin

func _2d_to_3d(footprint: Array):
	return footprint.map(func(vertex): return Vector3(vertex.x, 0, vertex.y))

func _has_gizmo(node):
	return node is BuildingBase

func _get_gizmo_name():
	return "FlatGizmos"

func _init():
	create_handle_material("handles")

func _redraw(gizmo: EditorNode3DGizmo):
	gizmo.clear()
	var node := gizmo.get_node_3d()
	gizmo.add_handles(_2d_to_3d(node.metadata.footprint), get_material("handles", gizmo), [])
	
	var lines = []
	for i in node.metadata.footprint.size() - 1:
		var from = node.metadata.footprint[i]
		var to = node.metadata.footprint[(i+1) % node.metadata.footprint.size()]
		lines.append(from)
		lines.append(to)
	
	gizmo.add_lines(_2d_to_3d(lines), StandardMaterial3D.new(), false)

func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
	return "Buidling vertex #" + str(handle_id)

func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
	var node := gizmo.get_node_3d()
	return node.metadata.footprint[handle_id]

func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var node := gizmo.get_node_3d()
	var plane := Plane(node.global_basis.y, node.global_position)
	var from := camera.project_ray_origin(screen_pos)
	var pos = plane.intersects_ray(from, camera.project_ray_normal(screen_pos) * 4096.0)
	if pos is Vector3:
		node.metadata.footprint[handle_id] = Vector2(node.to_local(pos).x, node.to_local(pos).z)
		
	node.update_gizmos()

func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, restore: Variant, cancel: bool) -> void:
	var undo_redo = UndoRedo.new()
	var node := gizmo.get_node_3d()
	if cancel:
		# Drag was canceled: restore original value (Godot gives it to you)
		node.metadata.footprint = restore
		return

	# Run your “on release” logic here:
	node.build()

	# Proper Undo/Redo for the change:
	undo_redo.create_action("Vertex Set")
	undo_redo.add_do_property(node, "some_property", node.metadata.footprint)
	undo_redo.add_undo_property(node, "some_property", restore)
	undo_redo.commit_action()
