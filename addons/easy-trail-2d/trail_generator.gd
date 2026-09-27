@tool
class_name TrailGenerator
extends CanvasGroup
## This class provides easy tools to generate visually accurate and dynamic 
## trails for existing elements, while staying performant and resource efficient

# TODO: consider making some of those overridable
const DEFAULT_CANVAS_GROUP_MATERIAL: Material = \
preload("res://addons/easy-trail-2d/materials/trail_canvas_group_material.tres")

const DEFAULT_TRAIL_PROCESS_MATERIAL: Material = \
preload("res://addons/easy-trail-2d/materials/trail_emitter_material.tres")

const DEFAULT_TRAIL_PARTICLE_MATERIAL: Material = \
preload("res://addons/easy-trail-2d/materials/trail_particle_material.tres")

# The threshold, in degrees above the horizontal line, 
# which classify the normalized movement direction as non-horizontal.
const VERTICAL_SPEED_THRESHOLD := cos(deg_to_rad(15))

# TODO: unify the two types into a single setting and abstract the differences
enum TrailType {STRETCH, GHOST}

enum SpreadMode {DISTANCE, TIME}

static var DYNAMIC_PROPERTIES: Array = [
	{
		"name": "spread_mode",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "Distance, Time",
	},
	(func(trail_generator: TrailGenerator) -> Array:
		if trail_generator.trail_type == TrailType.STRETCH:
			return [
				{
					"name": "dynamic_trail_head",
					"type": TYPE_BOOL,
					"hint": PROPERTY_HINT_NONE,
					"hint_string": "",
				},
			]
			
		else:
			return []),
	(func(trail_generator: TrailGenerator) -> Array:
		if trail_generator.automatic:
			return [
				{
					"name": "speed_threshold",
					"type": TYPE_FLOAT,
					"hint": PROPERTY_HINT_NONE,
					"hint_string": "",
				}
			]
			
		else:
			return [
				{
					"name": "enabled",
					"type": TYPE_BOOL,
					"hint": PROPERTY_HINT_NONE,
					"hint_string": "",
				}
			]),
	(func(trail_generator: TrailGenerator) -> Array:
		if trail_generator.spread_mode == SpreadMode.DISTANCE:
			return [
				{
					"name": "distance_spread",
					"type": TYPE_FLOAT,
					"hint": PROPERTY_HINT_NONE,
					"hint_string": "",
				},
				{
					"name": "reserved_frames",
					"type": TYPE_INT,
					"hint": PROPERTY_HINT_RANGE,
					"hint_string": "1, 100",
				},
			]
			
		elif trail_generator.spread_mode == SpreadMode.TIME:
			return [
				{
					"name": "time_spread",
					"type": TYPE_FLOAT,
					"hint": PROPERTY_HINT_RANGE,
					"hint_string": "0.01, 1, or_greater",
				}
			]
			
		else:
			return []),
]

## The list of nodes that will be trailed.
@export var targets: Array[Node2D]:
	set(value):
		if targets == value:
			return
		
		targets = value
		
		_update_snapshot_generator()

## The motion root of the trail, if not set will default to the
## first target in [member targets]
@export var pivot_node: Node2D:
	set(value):
		if pivot_node == value:
			return
		
		pivot_node = value
		
		_update_snapshot_generator()
	
	get():
		if _snapshot_generator:
			return _snapshot_generator.pivot_node
		
		return pivot_node

## The global rect within which we capture the elements.
## Does not imply texture quality, just extends and offsets
@export var snapshot_rect: Rect2i = Rect2i(-256, -256, 512, 512):
	set(value):
		if snapshot_rect == value:
			return
		
		snapshot_rect = value
		
		_update_snapshot_generator()

## This can be used to increase the quality of the trail snapshots, 
## will not affect the snapshot_rect size
@export var snapshot_resolution_scale: float = 1.0:
	set(value):
		if snapshot_resolution_scale == value:
			return
		
		snapshot_resolution_scale = value
		
		_update_snapshot_generator()
		_update_particles()

## An optimization where the trail will snapshot the targets
## once at its start, and use the same frame for the rest
## of its activation.
@export var single_snapshot: bool = false

# TODO: abstract these through better properties
## Whether the trail generates discrete snapshots of the element at 
## past positions or generates stretched snapshots that bridge between 
## past and present position
@export var trail_type: TrailType = TrailType.GHOST:
	set(value):
		if trail_type == value:
			return
		
		trail_type = value
		
		notify_property_list_changed()
		
		_update_particles()

## The lifetime of the generated trail particles
@export var trail_lifetime: float = 1.0:
	set(value):
		if trail_lifetime == value:
			return
		
		trail_lifetime = value
		
		_update_particles()

## Setting this to `true` would let the trail generator enable
## itself automatically based on *speed_threshold*
@export var automatic: bool = true:
	set(value):
		if automatic == value:
			return
		
		automatic = value
		
		notify_property_list_changed()

@export var trail_texture: Texture2D:
	set(value):
		if trail_texture == value:
			return
		
		trail_texture = value
		
		_update_canvas_group()

## The alpha curve of the particle, controlling it's opacity along 
## it's entire lifetime. 
## NOTE: Does not work with stretchy particles with sperad mode Distance.
@export var alpha_texture: Texture2D:
	set(value):
		if alpha_texture == value:
			return
		
		alpha_texture = value
		
		_update_canvas_group()

## This would make it so that the _leading_sprite, which dynamically stretches
## with the subject also gets visually updated. It is mainly relevant for 
## elements that significantly change while they move, and it will 
## require running the snapshot generation each frame, so use carefully
@export_storage var dynamic_trail_head: bool = false:
	set(value):
		if dynamic_trail_head == value:
			return
		
		dynamic_trail_head = value

## When enabled, you can manipulate [member look_direction],
## along side your movement of the character, and the result
## will be an intuitive sorting of the trail around your target.
## If you are moving upwards, the trail will be sorted on top of
## the target. If downwards, under. 
## The look direction will determine the sorting of the trail when
## moving perfectly horizontally. If facing downwards, the trail
## will be sorted below the target, and vice versa.
@export var movement_look_direction_sort: bool = false

## Define the speed threshold of the subject's movement
## in pixels per second for the trail generator to enable itself 
## when set to *automatic*
@export_storage var speed_threshold: float = 100.0

## This is overridden if *automatic* is true
@export_storage var enabled: bool = true:
	set(value):
		if enabled == value:
			return
		
		enabled = value

## Whether the trail generates based on distance traveled 
## or based on constant time intervals.
## It is export storage on purpose, so that it can appear in the
## correct place in the property list between custom properties
@export_storage var spread_mode: SpreadMode = SpreadMode.TIME:
	set(value):
		if spread_mode == value:
			return
		
		spread_mode = value
		
		notify_property_list_changed()
		
		_update_reserved_frames()

## How far (in global units) does the element have to travel to generate 
## a trail particle, teleportation over large distances is supported to spread
## trail particles evenly.
@export_storage var distance_spread: float = 25.0

## The minimum amount of desired separate sanpshot frames to use 
## when generating the trail. This would let you save past visuals of the 
## element. 
## Does not indicate final allocated frames count, but guarantees a minimum.
## When sperad mode is set to TIME, it is determined automatically, 
## But when spreading trail particles based on distance, a new snapshot
## can be required potentially every frame, making it impossible to automatically
## determine.
@export_storage var reserved_frames: int = 16:
	set(value):
		if reserved_frames == value:
			return
		
		reserved_frames = value
		
		_update_reserved_frames()

## The time intervals between trail particle generation when the trail generator is enabled.
## When spread_mode is set to TIME, it also affects the reserved frame count of the snapshot generator
## as more concurrent past snapshots require more texture storage.
@export_storage var time_spread: float = 0.1:
	set(value):
		if time_spread == value:
			return
		
		time_spread = value
		
		_update_reserved_frames()
		
		_update_particles()

## Use this in conjunction with [member movement_look_direction_sort] to 
## determine the sorting of the trail relatively to the target when moving
## horizontally.
var look_direction: Vector2

## Automatically being set taking 'enabled' and 'automatic' into account
var _is_enabled: bool = false:
	set(value):
		if value == _is_enabled:
			return
		
		_is_enabled = value
		
		if _is_enabled:
			_on_enabled()
			
		else:
			_on_disabled()

## The minimum amount of frames that the snapshot generator needs to 
## save into an atlas
var _reserved_frames: int = 1:
	set(value):
		if _reserved_frames == value:
			return
		
		_reserved_frames = value
		
		_update_snapshot_generator()
		
		_update_particles()

## The snapshot generator wrapped by this trail generator.
## It is in charge of managing snapshot atlases of the targets
var _snapshot_generator: SnapshotGenerator

## The particle emitter wrapped by this trail generator.
## It spawns particles that display the snapshots and automatically
## destroys them according to their lifetime.
var _particle_emitter: GPUParticles2D

## A sprite that sits at the head of the trail and used 
## for seamless generation of stretched trails
var _leading_sprite: Sprite2D

var _current_position: Vector2

## Used when generating particles and detecting target movement
var _past_position: Vector2

var _last_emit_position: Vector2

var _current_time: float = 0.0

var _past_time: float = 0.0

var _time_buffer: float = 0.0

var _last_emit_time: float = 0.0

var _distance_buffer: float = 0.0


#region Virtual Methods

func _init() -> void:
	if DisplayServer.get_name() == "headless":
		return
	
	texture_filter = TEXTURE_FILTER_NEAREST
	
	_snapshot_generator = SnapshotGenerator.new()


func _get_property_list() -> Array[Dictionary]:
	return _generate_dynamic_property_list_recursive(DYNAMIC_PROPERTIES)


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	
	add_child(_snapshot_generator)
	
	if !material:
		material = DEFAULT_CANVAS_GROUP_MATERIAL.duplicate()
	
	if Engine.is_editor_hint():
		var new_gizmo: SnapshotRectGizmo = SnapshotRectGizmo.new()
		
		new_gizmo.node = self
		
		add_child(new_gizmo)
	
	_update_canvas_group()
	
	# We want to generate the trail after the object has moved
	process_priority = 1
	
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	
	_update_reserved_frames()
	
	_snapshot_generator = SnapshotGenerator.new()
	
	_snapshot_generator.process_priority = 2
	
	# We put this after add_child() so that it will have the _sub_viewport children,
	# which it adds itself off its _ready(), by then.
	_update_snapshot_generator()
	
	var particle_material
	
	_particle_emitter = GPUParticles2D.new()
	
	_particle_emitter.emitting = false
	
	_particle_emitter.lifetime = 1.0
	
	# TODO @sphynx-owner: be more intentional
	_particle_emitter.amount = 1000
	
	# TODO @sphynx-owner: be more intentional
	_particle_emitter.fixed_fps = 120
	
	_particle_emitter.interpolate = false
	
	_particle_emitter.process_material = DEFAULT_TRAIL_PROCESS_MATERIAL
	
	_particle_emitter.material = DEFAULT_TRAIL_PARTICLE_MATERIAL
	
	_particle_emitter.texture = _snapshot_generator.atlas_texture_2d
	
	_particle_emitter.visibility_rect = Rect2(-100000, -100000, 200000, 200000)
	
	_particle_emitter.local_coords = false
	
	_particle_emitter.draw_order = GPUParticles2D.DRAW_ORDER_INDEX
	
	_particle_emitter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	add_child(_particle_emitter)
	
	_leading_sprite = Sprite2D.new()
	
	_leading_sprite.texture = _snapshot_generator.atlas_texture_2d
	
	_leading_sprite.material = DEFAULT_TRAIL_PARTICLE_MATERIAL
	
	_leading_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	_leading_sprite.set_instance_shader_parameter("manual", true)
	
	_leading_sprite.visible = false
	
	add_child(_leading_sprite)
	
	_update_particles()
	
	_past_position = _current_position
	
	_past_time = _current_time


func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	
	if !pivot_node:
		return
	
	_particle_emitter.set_instance_shader_parameter("game_frame", Engine.get_frames_drawn())
	
	_leading_sprite.set_instance_shader_parameter("game_frame", Engine.get_frames_drawn())
	
	_current_position = get_pivot_position()
	
	_current_time = _get_time()
	
	var _frame_movement: Vector2 = _current_position - _past_position
	
	var _frame_speed: float = _frame_movement.length()
	
	if movement_look_direction_sort:
		var normalized_velocity: Vector2 = _frame_movement.normalized()
		
		var is_horizontal: bool = abs(normalized_velocity.x) > VERTICAL_SPEED_THRESHOLD
		
		var target_z_index: int = pivot_node.z_index
		
		if is_horizontal:
			z_index = target_z_index + (1 if look_direction.y < 0 else -1)
			
		else:
			z_index = target_z_index + (1 if normalized_velocity.y < 0 else -1)
	
	var speed: float = _frame_speed / delta
	
	_is_enabled = (speed > speed_threshold) if automatic else enabled
	
	if _is_enabled:
		if trail_type == TrailType.STRETCH:
			if dynamic_trail_head:
				_snapshot_generator.queue_snapshot(false)
			
			_update_leading_sprite()
		
		match spread_mode:
			SpreadMode.TIME:
				_time_spread_process(delta)
			
			SpreadMode.DISTANCE:
				_distance_spread_process(_frame_movement)
		
	
	_past_position = _current_position
	
	_past_time = _current_time

#endregion

#region Public Methods

#endregion

#region Private Methods

## This function makes it easier for me to create dynamically accessible properties 
## with support for nested property workflow. 
func _generate_dynamic_property_list_recursive(
	dynamic_property_list: Array,
	_result_property_list: Array[Dictionary] = []
) -> Array[Dictionary]:
	for member in dynamic_property_list:
		if member is Callable:
			_generate_dynamic_property_list_recursive(member.call(self), _result_property_list)
			
		else:
			_result_property_list.append(member)
	
	return _result_property_list


func _update_reserved_frames() -> void:
	match spread_mode:
		SpreadMode.DISTANCE:
			_reserved_frames = reserved_frames
		
		SpreadMode.TIME:
			_reserved_frames = min(ceil(trail_lifetime / time_spread) + 1, 100)


func _update_snapshot_generator() -> void:
	if !_snapshot_generator:
		return
	
	_snapshot_generator.pivot_node = pivot_node
	
	_snapshot_generator.targets = targets
	
	_snapshot_generator.snapshot_rect = snapshot_rect
	
	_snapshot_generator.snapshot_resolution_scale = snapshot_resolution_scale
	
	# It is easier to simply create the smallest square atlas to contain the required 
	# reserved frames count.
	var dimension: int = ceil(sqrt(_reserved_frames))
	
	_snapshot_generator.atlas_dimensions = Vector2i(dimension, dimension)


func _update_canvas_group() -> void:
	if !material:
		return
	
	material.set_shader_parameter("trail_texture", trail_texture)
	material.set_shader_parameter("alpha_texture", alpha_texture)


func _update_particles() -> void:
	if !_particle_emitter:
		return
	
	_particle_emitter.lifetime = trail_lifetime
	
	_particle_emitter.set_instance_shader_parameter("atlas_h_frames", _snapshot_generator.atlas_dimensions.x)
	
	_particle_emitter.set_instance_shader_parameter("atlas_v_frames", _snapshot_generator.atlas_dimensions.y)
	
	_particle_emitter.set_instance_shader_parameter("snapshot_resolution_scale", snapshot_resolution_scale)
	
	_particle_emitter.set_instance_shader_parameter("sample_count", 5)
	
	_leading_sprite.set_instance_shader_parameter("atlas_h_frames", _snapshot_generator.atlas_dimensions.x)
	
	_leading_sprite.set_instance_shader_parameter("atlas_v_frames", _snapshot_generator.atlas_dimensions.y)
	
	_leading_sprite.set_instance_shader_parameter("snapshot_resolution_scale", snapshot_resolution_scale)
	
	_leading_sprite.set_instance_shader_parameter("sample_count", 5)


func get_pivot_position() -> Vector2:
	if DisplayServer.get_name() == "headless":
		return Vector2.ZERO
	
	return _snapshot_generator.get_pivot_position()


func _get_time() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_enabled() -> void:
	_last_emit_time = _past_time
	_last_emit_position = _past_position
	
	_time_buffer = time_spread if trail_type == TrailType.GHOST else 0.0
	
	_distance_buffer = distance_spread if trail_type == TrailType.GHOST else 0.0


func _on_disabled() -> void:
	if _last_emit_position != _past_position and trail_type == TrailType.STRETCH:
		_emit_stretchy_particle()
	
	_leading_sprite.visible = false


func _time_spread_process(delta: float) -> void:
	_time_buffer += delta
	
	if _time_buffer > time_spread:
		if !single_snapshot:
			_snapshot_generator.queue_snapshot()
		
		match trail_type:
			TrailType.GHOST:
				_emit_particle(_past_position, _snapshot_generator.get_current_frame())
			
			TrailType.STRETCH:
				_emit_stretchy_particle()
		
		_time_buffer = fmod(_time_buffer, time_spread)


func _distance_spread_process(delta: Vector2) -> void:
	var speed: float = delta.length()
	
	_distance_buffer += speed
	
	if _distance_buffer > distance_spread:
		if !single_snapshot:
			_snapshot_generator.queue_snapshot()
		
		match trail_type:
			TrailType.GHOST:
				var starting_distance: float = distance_spread - (_distance_buffer - speed)
				
				var direction: Vector2 = delta.normalized()
				
				var emit_position: Vector2 = _past_position + direction * starting_distance
				
				for i in int(_distance_buffer / distance_spread):
					_emit_particle(emit_position, _snapshot_generator.get_current_frame())
					emit_position += direction * distance_spread
			
			TrailType.STRETCH:
				_emit_stretchy_particle()
		
		_distance_buffer = fmod(_distance_buffer, distance_spread)


func _emit_stretchy_particle() -> void:
	var stretch: Vector2 = _last_emit_position - _current_position
	
	var particle_stretch_time: float = _current_time - _last_emit_time
	
	_emit_particle(_current_position, _snapshot_generator.get_current_frame(), stretch, particle_stretch_time)
	
	_last_emit_position = _current_position
	
	_last_emit_time = _current_time


func _emit_particle(p_position: Vector2, atlas_frame: float, stretch: Vector2 = Vector2.ZERO, stretch_time: float = 0.0) -> void:
	_particle_emitter.emit_particle(
		Transform2D(0, p_position),
		Vector2(),
		Color(stretch_time, atlas_frame, 0, 1.0),
		# HACK @sphynx-owner: we reserve the green channel for the age of the particle, 
		Color(stretch.x, 0, stretch.y, trail_lifetime),
		GPUParticles2D.EMIT_FLAG_POSITION | GPUParticles2D.EMIT_FLAG_CUSTOM | GPUParticles2D.EMIT_FLAG_COLOR
	)


func _update_leading_sprite() -> void:
	_leading_sprite.global_position = get_pivot_position()
	
	_leading_sprite.visible = trail_type == TrailType.STRETCH
	
	_leading_sprite.set_instance_shader_parameter("manual", true)
	_leading_sprite.set_instance_shader_parameter("manual_atlas_frame", _snapshot_generator.get_current_frame())
	_leading_sprite.set_instance_shader_parameter("manual_stretch_offset", _last_emit_position - _current_position)
	_leading_sprite.set_instance_shader_parameter("manual_stretch_time", _current_time - _last_emit_time)
	_leading_sprite.set_instance_shader_parameter("manual_age", 0)
	_leading_sprite.set_instance_shader_parameter("manual_lifespan", trail_lifetime)

#endregion
