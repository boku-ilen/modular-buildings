extends Node

@export var building_base: BuildingBase
@export var metadata: BuildingMetadata
@export var test_type: TestType
enum TestType {
	Creation,
	Rendering
}
@export var num_instances := 100
var instance_roots = []

func _ready() -> void:
	if test_type == TestType.Rendering:
		for i in range(num_instances):
			var instance = Node3D.new()
			add_child(instance)
			instance.position += Vector3(randf_range(-100, 100), randf_range(-100,100), randf_range(-100,100))
			instance_roots.append(instance)
			BuildingFactory.build_building(instance, metadata)

func _process(delta: float) -> void:
	if test_type == TestType.Creation:
		building_base.teardown()
		building_base.build()
	elif test_type == TestType.Rendering:
		pass
	#print("built")