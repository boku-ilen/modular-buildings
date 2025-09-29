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
		for i in range(mesh.get_surface_count()):
			set_instance_shader_parameter("bend", deg_to_rad(new_angle))
		
		rotation_degrees.y = (new_angle - 90)
