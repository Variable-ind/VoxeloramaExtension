extends "res://src/Tools/Draw.gd"

var _last_position := Vector2.INF

var _depth_array := []  # 2D array
var _depth := 1.0
var _canvas_depth: PackedScene = preload("res://src/Extensions/Voxelorama/Tools/CanvasDepth.tscn")
var _canvas_depth_node: Node2D

var _canvas: Node2D
var _draw_points := []


func _ready() -> void:
	kname = name.replace(" ", "_").to_lower()
	load_config()

	_canvas = ExtensionsApi.general.get_canvas()
	for child in _canvas.get_children():
		if child.is_in_group("CanvasDepth"):
			_canvas_depth_node = child
			_canvas_depth_node.users += 1
			# We will share single _canvas_depth_node
			return
	_canvas_depth_node = _canvas_depth.instance()
	_canvas.add_child(_canvas_depth_node)


func save_config() -> void:
	var config := get_config()
	ExtensionsApi.general.get_config_file().set_value(tool_slot.kname, kname, config)


func load_config() -> void:
	var value = ExtensionsApi.general.get_config_file().get_value(tool_slot.kname, kname, {})
	set_config(value)
	update_config()


func get_config() -> Dictionary:
	return {"depth": _depth}


func set_config(config: Dictionary) -> void:
	_depth = config.get("depth", _depth)


func update_config() -> void:
	.update_config()
	$Depth.value = _depth


func draw_start(position: Vector2) -> void:
	is_moving = true
	_depth_array = []
	var project = ExtensionsApi.project.get_current_project()
	var cel: Reference = project.frames[project.current_frame].cels[project.current_layer]
	var image: Image = cel.image
	if cel.has_meta("VoxelDepth"):
		var image_depth_array: Array = cel.get_meta("VoxelDepth")
		var n_array_pixels: int = image_depth_array.size() * image_depth_array[0].size()
		var n_image_pixels: int = image.get_width() * image.get_height()

		if n_array_pixels == n_image_pixels:
			_depth_array = image_depth_array
		else:
			_initialize_array(image)
	else:
		_initialize_array(image)
	_update_array(cel, position)
	_last_position = position


func draw_move(position: Vector2) -> void:
	# This can happen if the user switches between tools with a shortcut
	# while using another tool
	if !is_moving:
		draw_start(position)
	var project = ExtensionsApi.project.get_current_project()
	var cel = project.frames[project.current_frame].cels[project.current_layer]
	fill_gap(cel, _last_position, position)
	_last_position = position


func draw_end(position: Vector2) -> void:
	is_moving = false
	var project = ExtensionsApi.project.get_current_project()
	var cel = project.frames[project.current_frame].cels[project.current_layer]
	_update_array(cel, position)


func cursor_move(position: Vector2) -> void:
	_cursor = position


func _initialize_array(image: Image) -> void:
	for x in image.get_width():
		_depth_array.append([])
		for y in image.get_height():
			_depth_array[x].append(1)


func _update_array(cel: Reference, position: Vector2) -> void:
	_prepare_tool()
	var coords_to_draw := _draw_tool(position)
	for coord in coords_to_draw:
		if ExtensionsApi.project.get_current_project().can_pixel_get_drawn(coord):
			_depth_array[coord.x][coord.y] = _depth
	cel.set_meta("VoxelDepth", _depth_array)
	_canvas_depth_node.update()


func _on_Depth_value_changed(value: float) -> void:
	_depth = value
	update_config()
	save_config()


func _exit_tree() -> void:
	if _canvas:
		_canvas_depth_node.request_deletion()
		if is_moving:
			draw_end(_canvas.current_pixel.floor())


# overrides
# Make sure to always have invoked _prepare_tool() before this. This computes the coordinates to be
# drawn if it can (except for the generic brush, when it's actually drawing them)
func _draw_tool(position: Vector2) -> PoolVector2Array:
	_draw_points.clear()
	match _brush.type:
		Brushes.PIXEL:
			return _compute_draw_tool_pixel(position)
		Brushes.CIRCLE:
			return _compute_draw_tool_circle(position, false)
		Brushes.FILLED_CIRCLE:
			return _compute_draw_tool_circle(position, true)
		_:
			return _compute_draw_tool_brush(position)


# helper methods
func _compute_draw_tool_brush(position: Vector2) -> PoolVector2Array:
	var result := PoolVector2Array()
	var brush_mask := BitMap.new()
	var pos = position - (_indicator.get_size() / 2).floor()
	brush_mask.create_from_image_alpha(_brush_image, 0.0)
	for x in brush_mask.get_size().x:
		for y in brush_mask.get_size().y:
			if !_draw_points.has(Vector2(x, y)):
				if brush_mask.get_bit(Vector2(x, y)):
					result.append(pos + Vector2(x, y))
	return result


# Bresenham's Algorithm
# Thanks to https://godotengine.org/qa/35276/tile-based-line-drawing-algorithm-efficiency
func fill_gap(cel, start: Vector2, end: Vector2) -> void:
	var dx := int(abs(end.x - start.x))
	var dy := int(-abs(end.y - start.y))
	var err := dx + dy
	var e2 := err << 1
	var sx = 1 if start.x < end.x else -1
	var sy = 1 if start.y < end.y else -1
	var x = start.x
	var y = start.y
	while !(x == end.x && y == end.y):
		e2 = err << 1
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
		_update_array(cel, Vector2(x, y))
