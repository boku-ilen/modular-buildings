@tool
extends MeshInstance3D
class_name HingeCorner

@export_range(0., 360., 1.) var angle := 90. : 
	set(new_angle):
		angle = new_angle
		if new_angle > 180:
			new_angle = new_angle / 2 + 135
		else:
			new_angle = new_angle / 2 - 45
		material_override.set_shader_parameter("bend", deg_to_rad(new_angle))
