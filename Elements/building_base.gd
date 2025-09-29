@tool
extends Node3D
class_name BuildingBase


@export_tool_button("Build!") var build_it = build
@export var metadata: BuildingMetadata

func _ready():
	update_gizmos()
	metadata.changed.connect(build)


func build():
	for child in $Elements.get_children():
		child.queue_free()
	BuildingFactory.build_building($Elements, metadata)
	set_owner_recursive($Elements)


func set_owner_recursive(node: Node):
	for child in node.get_children():
		set_owner_recursive(child)
	node.set_owner(get_tree().edited_scene_root)
