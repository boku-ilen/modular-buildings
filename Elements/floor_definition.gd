extends Resource
class_name FloorDefinition

@export var walls: Array[Mesh]
@export var door: Mesh
@export var corner_90: Mesh
@export var corner_270: Mesh
# A minimal element to fill where other assets do not fit
@export var spacer_block: Mesh
@export var height := 3.

func _init(_walls, _door, _corner_90, _corner_270, _spacer_block, _height:=3.) -> void:
	door = _door
	corner_90 = _corner_90
	corner_270 = _corner_270
	walls = _walls
	spacer_block = _spacer_block
	height = _height
