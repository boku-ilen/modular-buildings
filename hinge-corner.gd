@tool
extends MeshInstance3D
class_name HingeCorner

@export_range(0., 360., 1.) var angle := 90. : 
	set(new_angle):
		angle = new_angle
		# As both outer ends of the mesh are pivoted, we need the extralogic
		# because otherwise we go a "full circle" 
		if new_angle > 180:
			new_angle = new_angle / 2 + 135
		else:
			new_angle = new_angle / 2 - 45
		for i in range(get_surface_override_material_count()):
			get_surface_override_material(i).set_shader_parameter("bend", deg_to_rad(new_angle))
		
		rotation_degrees.y = (new_angle - 90)
		custom_aabb = recomoputed_aabb(new_angle)

#var debug1
#var debug2
#func _ready() -> void:
	#debug1 = preload("res://util/debug_mesh2.tscn").instantiate()
	#debug2 = preload("res://util/debug_mesh.tscn").instantiate()
	#add_child(debug1)
	#add_child(debug2)

# Recompute the axis aligned bounding box based on the angle that modifies
# the geometry of the corner in the shader
func recomoputed_aabb(new_angle) -> AABB:
	var common_aabb = mesh.get_aabb()
	
	var rotation_matrix = Basis(
		Vector3(cos(angle), 0., -sin(angle)),
		Vector3(0., 1., 0.),
		Vector3(sin(angle), 0., cos(angle))
	)
	
	var new_start = common_aabb.position.rotated(Vector3.UP, -(PI / 2 - deg_to_rad(new_angle)))
	var new_end = common_aabb.end.rotated(Vector3.UP, (PI / 2 - deg_to_rad(new_angle)))
	var new_size = new_end - new_start
	
	#debug1.position = new_start
	#debug2.position = new_end
	
	var merged = AABB(new_start, new_size).abs().expand(Vector3.ZERO)
	return merged
