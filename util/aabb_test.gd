@tool
extends Node3D

@export var scene : PackedScene : 
	set(new_packed):
		scene = new_packed
		if instance:
			instance.queue_free()
		instance = new_packed.instantiate()
		add_child(instance)
var instance: Node3D

@export var check : bool :
	set(new_c):
		parent.queue_free()
		parent = Node3D.new()
		add_child(parent)
		test()

var parent := Node3D.new()

func test():
	var aabb = get_combined_aabb(instance).abs()
	
	var d = load("res://util/debug_mesh2.tscn").instantiate()
	d.scale = Vector3.ONE * 0.2
	d.material_override = d.material_override.duplicate()
	d.material_override.albedo_color = Color.SKY_BLUE
	d.position = Vector3(aabb.end)
	parent.add_child(d)
	var d2 = load("res://util/debug_mesh2.tscn").instantiate()
	d2.scale = Vector3.ONE * 0.2
	d2.material_override = d.material_override.duplicate()
	d2.material_override.albedo_color = Color.DARK_RED
	d2.position = Vector3(aabb.position)
	parent.add_child(d2)


static func get_combined_aabb(instance: Node3D, aabb: AABB = AABB()) -> AABB:
	for child in instance.get_children():
		if not child is Node3D: continue
		aabb = get_combined_aabb(child, aabb)
	
	if instance is VisualInstance3D:
		return aabb.merge(instance.get_aabb())
	return aabb
