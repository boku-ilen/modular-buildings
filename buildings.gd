@tool
extends Node3D


@export_group("Controls")
@export var build_it: bool:
	set(_none):
		if building != null:
			for child in building.get_children(): 
				child.queue_free()
				await(child.tree_exited)
		build()
@export var reset_it: bool: 
	set(_none): reset()

static func polar_vertices(num_verts: int, radius):
	var angle: float = 2*PI / num_verts
	var vertices := []
	for i in range(num_verts):
		vertices.append(Vector2(sin(angle * (num_verts - i)) * radius, cos(angle * (num_verts - i)) * radius))
	return vertices as Array[Vector2]

const DUMB_SCALER = 5.2
var preset_definitions = [
	Array([
		Vector2(-5, -5),
		Vector2(5, -5),
		Vector2(5, 5),
		Vector2(-5, 5),
	]) as Array[Vector2],
	# Built using polar vertices in enter tree
	[] as Array[Vector2],
	([
		Vector2(3, -8) * DUMB_SCALER, Vector2(3, 8) * DUMB_SCALER, Vector2(-3, 8) * DUMB_SCALER, Vector2(-3, 4) * DUMB_SCALER, Vector2(0, 4) * DUMB_SCALER,
		Vector2(0, 1) * DUMB_SCALER, Vector2(-3, 1) * DUMB_SCALER, Vector2(-3, -2) * DUMB_SCALER, Vector2(0, -2) * DUMB_SCALER, Vector2(0, -5) * DUMB_SCALER,
		Vector2(-3, -5) * DUMB_SCALER, Vector2(-3, -8) * DUMB_SCALER
	]) as Array[Vector2],
	Array([
		Vector2(-10, -5),
		Vector2(10, -5),
		Vector2(10, 5),
		Vector2(-10, 5)
	]) as Array[Vector2],
	Array([
		Vector2(-40, -40),
		Vector2(40, -40),
		Vector2(40, -10),
		Vector2(-10, -10),
		Vector2(-10, 40),
		Vector2(-40, 40)
	]) as Array[Vector2],
]

enum FOOTPRINT_PRESETS {
	SQUARE,
	CIRCULAR,
	E_SHAPED,
	RECTANGLE,
	L_SHAPED
}

@export_group("Meta")
@export var height := 8.0: 
	set(new_height):
		height = new_height
		metadata.height = new_height
@export var floors := 3
@export var footprint: Array = preset_definitions[FOOTPRINT_PRESETS.SQUARE]: 
	set(new_footprint): 
		footprint = new_footprint
		metadata.footprint = new_footprint
@export var foot_print_presets: FOOTPRINT_PRESETS:
	set(new_preset):
		foot_print_presets = new_preset
		footprint = preset_definitions[new_preset]
		metadata.footprint = footprint as Array[Vector2]


var door = preload("res://modular_urban_apartments_facade_4k.blend/elements/door.glb")
var wall = preload("res://modular_urban_apartments_facade_4k.blend/elements/wall.glb")
var window2 = preload("res://modular_urban_apartments_facade_4k.blend/elements/window2.glb")
var window = preload("res://modular_urban_apartments_facade_4k.blend/elements/window.glb")
var windows = preload("res://modular_urban_apartments_facade_4k.blend/elements/windows.glb")
var corner = preload("res://modular_urban_apartments_facade_4k.blend/elements/corner.glb")
var corner2 = preload("res://modular_urban_apartments_facade_4k.blend/elements/corner2.glb")
var corner_270 = preload("res://modular_urban_apartments_facade_4k.blend/elements/corner_270.glb")
var corner2_270 = preload("res://modular_urban_apartments_facade_4k.blend/elements/corner2_270.glb")
var space_block = preload("res://modular_urban_apartments_facade_4k.blend/elements/space_block.glb")
var corner_bot = preload("res://modular_urban_apartments_facade_4k.blend/elements/corner_bot.glb")
var corner_270_bot = preload("res://modular_urban_apartments_facade_4k.blend/elements/corner_270_bot.glb")
var corner_top = preload("res://modular_urban_apartments_facade_4k.blend/elements/corner_top.glb")
var corner_270_top = preload("res://modular_urban_apartments_facade_4k.blend/elements/corner_270_top.glb")
var wall_bot = preload("res://modular_urban_apartments_facade_4k.blend/elements/bot_wall.glb")
var wall_top = preload("res://modular_urban_apartments_facade_4k.blend/elements/top_wall.glb")
var bot_spacer = preload("res://modular_urban_apartments_facade_4k.blend/elements/bot_spacer.glb")

func define_floors(_metadata: BuildingMetadata):
	_metadata.floor_definitions = [
		BuildingMetadata.FloorDefinition.new(
			[wall_bot, wall_bot, wall_bot, wall_bot],
			null,
			corner_bot,
			corner_270_bot,
			bot_spacer,
			0.7
		),
		BuildingMetadata.FloorDefinition.new(
			[wall, window, window2, windows],
			door,
			corner,
			corner_270,
			space_block
		),
		BuildingMetadata.FloorDefinition.new(
			[wall, window, window2, windows],
			null,
			corner,
			corner_270,
			space_block
		),
		BuildingMetadata.FloorDefinition.new(
			[wall, window, window2, windows],
			null,
			corner,
			corner_270,
			space_block
		),
		BuildingMetadata.FloorDefinition.new(
			[wall, window, window2, windows],
			null,
			corner,
			corner_270,
			space_block
		),
		BuildingMetadata.FloorDefinition.new(
			[wall_top, wall_top, wall_top, wall_top],
			null,
			corner_top,
			corner_270_top,
			preload("res://modular_urban_apartments_facade_4k.blend/elements/bot_spacer.glb"),
			0.95
		),
	] as Array[BuildingMetadata.FloorDefinition]
var metadata := BuildingMetadata.new()
var building: Node3D


func build():
	preset_definitions[1] = polar_vertices(16, 20)
	define_floors(metadata)
	building = BuildingFactory.build_building(metadata)
	add_child(building)


func reset():
	building.queue_free()
