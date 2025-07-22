extends Resource
class_name BuildingMetadata


class FloorDefinition:
	var walls: Array
	var door: PackedScene
	var corner_90: PackedScene
	var corner_270: PackedScene
	# A minimal element to fill where other assets do not fit
	var spacer_block: PackedScene
	var height := 3.
	
	func _init(_walls, _door, _corner_90, _corner_270, _spacer_block, _height:=3.) -> void:
		door = _door
		corner_90 = _corner_90
		corner_270 = _corner_270
		walls = _walls
		spacer_block = _spacer_block
		height = _height

var floor_definitions: Array[FloorDefinition]
var building_height: float
var roof_height: float
var footprint: Array
