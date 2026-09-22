@tool
class_name TrailGenerator
extends CanvasGroup
## This class provides easy tools to generate visually accurate and dynamic 
## trails for existing elements, while staying performant and resource efficient

# TODO: consider making some of those overridable
const DEFAULT_CANVAS_GROUP_MATERIAL: Material = \
preload("res://addons/easy-trail-2d/materials/default_canvas_group_material.tres")

const DEFAULT_TRAIL_PROCESS_MATERIAL: Material = \
preload("res://addons/easy-trail-2d/materials/default_trail_shader_material.tres")

const DEFAULT_TRAIL_PARTICLE_MATERIAL: Material = \
preload("res://addons/easy-trail-2d/materials/default_trail_particle_material.tres")

# The threshold, in degrees above the horizontal line, 
# which classify the normalized movement direction as non-horizontal.
const VERTICAL_SPEED_THRESHOLD := cos(deg_to_rad(15))

# TODO: unify the two types into a single setting and abstract the differences
enum TrailType {STRETCH, GHOST}

enum SpreadMode {DISTANCE, TIME}

static var DYNAMIC_PROPERTIES: Array = [
	(func(trail_generator: TrailGenerator) -> Array:
		if trail_generator.trail_type == TrailType.STRETCH:
			return [
				{
					"name": "dynamic_trail_head",
					"type": TYPE_BOOL,
					"hint": PROPERTY_HINT_NONE,
					"hint_string": "",
				},
				(func(trail_generator: TrailGenerator) -> Array:
					if trail_generator.spread_mode == SpreadMode.TIME:
						return [
							{
								"name": "alpha_curve",
								"type": TYPE_OBJECT,
								"hint": PROPERTY_HINT_RESOURCE_TYPE,
								"hint_string": "CurveTexture",
							}
						]
					return []),
			]
		return [
			{
				"name": "alpha_curve",
				"type": TYPE_OBJECT,
				"hint": PROPERTY_HINT_RESOURCE_TYPE,
				"hint_string": "CurveTexture",
			}
		]),
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
		return [
			{
				"name": "enabled",
				"type": TYPE_BOOL,
				"hint": PROPERTY_HINT_NONE,
				"hint_string": "",
			}
		]),
	{
		"name": "spread_mode",
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "Distance, Time",
	},
	(func(trail_generator: TrailGenerator) -> Array:
		if trail_generator.spread_mode == SpreadMode.TIME:
			return [
				{
					"name": "time_spread",
					"type": TYPE_FLOAT,
					"hint": PROPERTY_HINT_RANGE,
					"hint_string": "0.01, 1, or_greater",
				}
			]
		return []),
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
		return []),
]

# TODO: Replace this with a custom property wrapper to a quick search 
# dictionary for efficient add and remove operations at runtime
## The list of nodes that will be trailed. Note that 
## they have to have a supporting shader materail that has the 
## includes from the snapshot generator, refer to /example/shaders/trailable_sprite.gdshader
## NOTE: Do not modify this array from code, instead use the access functions
@export var targets: Array[Node2D]:
	set(value):
		if targets == value:
			return
		
		targets = value
		
		_update_snapshot_generator()

## The motion root of the trail, is not necessarily trailed itself.
## For when multiple nodes are targets under the same trail generator
@export var pivot_node: Node2D:
	set(value):
		if pivot_node == value:
			return
		
		pivot_node = value
		
		_update_snapshot_generator()

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
		_update_particle_emitter()

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
		
		_update_particle_emitter()

## The lifetime of the generated trail particles
@export var trail_lifetime: float = 1.0:
	set(value):
		if trail_lifetime == value:
			return
		
		trail_lifetime = value
		
		_update_particle_emitter()

## Setting this to `true` would let the trail generator enable
## itself automatically based on *speed_threshold*
@export var automatic: bool = true:
	set(value):
		if automatic == value:
			return
		
		automatic = value
		
		notify_property_list_changed()

## Whether to emit a last trail particle even if not qualified 
## for emission when the generation is disabled (distance based 
## dashes looks fuller at the end point)
@export var emit_particle_on_disabled: bool = true

## The alpha curve of the particle, controlling it's opacity along 
## it's entire lifetime. 
## NOTE: Does not work with stretchy particles with sperad mode Distance.
@export_storage var alpha_curve: CurveTexture = CurveTexture.new():
	set(value):
		if alpha_curve == value:
			return
		
		alpha_curve = value
		
		_update_particle_emitter()

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
		
		_update_particle_emitter()

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
		
		_update_particle_emitter()

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

## The minimum amount of frames that th esnapshot generator needs to 
## save into an atlas
var _reserved_frames: int = 1:
	set(value):
		if _reserved_frames == value:
			return
		
		_reserved_frames = value
		
		_update_snapshot_generator()
		
		_update_particle_emitter()

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

## This will let the _second_leading_sprite make itself invisible
## after the trail duration of a similarly spawned particle.
var _set_invisible_timer: SceneTreeTimer

## Used when generating particles and detecting target movement
var _past_position: Vector2

## The displacement of the target during this frame
var _frame_movement: Vector2 = Vector2.ZERO

## The dispalcement length of the target during this frame
var _frame_speed: float = 0.0

## Buffers for detecting when to generate trail particles
var _time_buffer: float = 0.0

var _distance_buffer: float = 0.0

## Used for generating connected trails
var _stretch_past_position: Vector2

## Will let us detect single teleportation and behave differently based on that
var _just_started: bool = false

## Uesd when the trail generator spawns and only later gets its target.
var _first_process_since_spawn: bool = true


#region Virtual Methods

func _init() -> void:
	if Engine.is_editor_hint():
		return
	
	texture_filter = TEXTURE_FILTER_NEAREST


func _get_property_list() -> Array[Dictionary]:
	return _generate_dynamic_property_list_recursive(DYNAMIC_PROPERTIES)


func _ready() -> void:
	if !material:
		material = DEFAULT_CANVAS_GROUP_MATERIAL
	
	if Engine.is_editor_hint():
		return

	if DisplayServer.get_name() == "headless":
		return
	
	# We want to generate the trail after the object has moved
	process_priority = 1
	
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	
	_update_reserved_frames()
	
	_snapshot_generator = SnapshotGenerator.new()
	
	_snapshot_generator.process_priority = 2
	
	# We put this after add_child() so that it will have the _sub_viewport children,
	# which it adds itself off its _ready(), by then.
	_update_snapshot_generator()
	
	add_child(_snapshot_generator)
	
	_particle_emitter = GPUParticles2D.new()
	
	_particle_emitter.emitting = false
	
	_particle_emitter.amount = 1000
	
	_particle_emitter.process_material = DEFAULT_TRAIL_PROCESS_MATERIAL
	
	_particle_emitter.material = DEFAULT_TRAIL_PARTICLE_MATERIAL.duplicate()
	
	_particle_emitter.texture = _snapshot_generator.atlas_texture_2d
	
	_particle_emitter.visibility_rect = Rect2(-100000, -100000, 200000, 200000)
	
	_particle_emitter.local_coords = false
	
	_particle_emitter.draw_order = GPUParticles2D.DRAW_ORDER_INDEX
	
	_particle_emitter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	_particle_emitter.interpolate = false
	
	add_child(_particle_emitter)
	
	_leading_sprite = Sprite2D.new()
	
	_leading_sprite.texture = _snapshot_generator.atlas_texture_2d
	
	_leading_sprite.material = DEFAULT_TRAIL_PARTICLE_MATERIAL.duplicate()
	
	_leading_sprite.set_instance_shader_parameter("use_override_offset", true)
	
	_leading_sprite.visible = false
	
	add_child(_leading_sprite)
	
	_update_particle_emitter()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	_trail_process(delta)

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


func _update_particle_emitter() -> void:
	if !_particle_emitter:
		return
	
	set_instance_shader_parameter(
		"use_canvas_group_alpha_curve",
		trail_type == TrailType.STRETCH and spread_mode == SpreadMode.TIME
	)
	
	_particle_emitter.lifetime = trail_lifetime
	
	# The particles all share the same texture. While somewhat more complicated, it is also more 
	# efficient to write snapshots into a static atlas.
	_particle_emitter.set_instance_shader_parameter("snapshot_resolution_scale", snapshot_resolution_scale)
	
	_particle_emitter.set_instance_shader_parameter("particles_anim_h_frames", _snapshot_generator.atlas_dimensions.x)
	
	_particle_emitter.set_instance_shader_parameter("particles_anim_v_frames", _snapshot_generator.atlas_dimensions.y)
	
	_particle_emitter.material.set_shader_parameter("alpha_curve", alpha_curve)
	
	_particle_emitter.set_instance_shader_parameter(
		"use_canvas_group_alpha_curve",
		trail_type == TrailType.STRETCH and spread_mode == SpreadMode.TIME
	)
	
	_particle_emitter.set_instance_shader_parameter("time_spread", time_spread)
	
	_particle_emitter.set_instance_shader_parameter("lifetime", trail_lifetime)
	
	_leading_sprite.set_instance_shader_parameter("snapshot_resolution_scale", snapshot_resolution_scale)
	
	_leading_sprite.set_instance_shader_parameter("particles_anim_h_frames", _snapshot_generator.atlas_dimensions.x)
	
	_leading_sprite.set_instance_shader_parameter("particles_anim_v_frames", _snapshot_generator.atlas_dimensions.y)
	
	_leading_sprite.material.set_shader_parameter("alpha_curve", alpha_curve)
	
	_leading_sprite.set_instance_shader_parameter(
		"use_canvas_group_alpha_curve",
		trail_type == TrailType.STRETCH and spread_mode == SpreadMode.TIME
	)
	
	_leading_sprite.set_instance_shader_parameter("time_spread", time_spread)
	
	_leading_sprite.set_instance_shader_parameter("lifetime", trail_lifetime)


func _trail_process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	
	if !pivot_node:
		return
	
	if _first_process_since_spawn:
		_past_position = _get_pivot_node_position()
		
		_stretch_past_position = _past_position
	
	_frame_movement = _get_pivot_node_position() - _past_position
	
	_frame_speed = _frame_movement.length()
	
	if movement_look_direction_sort:
		var normalized_velocity: Vector2 = _frame_movement.normalized()
		
		var is_horizontal: bool = abs(normalized_velocity.x) > VERTICAL_SPEED_THRESHOLD
		
		var target_z_index: int = pivot_node.z_index
		
		if is_horizontal:
			z_index = target_z_index + (1 if look_direction.y < 0 else -1)
			
		else:
			z_index = target_z_index + (1 if normalized_velocity.y < 0 else -1)
	
	var past_is_enabled: bool = _is_enabled
	
	_update_enabled(delta)
	
	if !past_is_enabled and _is_enabled and _just_started == false:
		_just_started = true
		
	else:
		_just_started = false
	
	if _is_enabled:
		match trail_type:
			TrailType.GHOST:
				match spread_mode:
					SpreadMode.TIME:
						_ghost_time_process(delta)
					
					SpreadMode.DISTANCE:
						_ghost_distance_process()
			
			TrailType.STRETCH:
				if dynamic_trail_head:
					_snapshot_generator.queue_snapshot(false)
				
				_leading_sprite.global_position = _get_pivot_node_position()
				
				_sync_leading_sprite_visual()
				
				match spread_mode:
					SpreadMode.TIME:
						_stretch_time_process(delta)
					
					SpreadMode.DISTANCE:
						_stretch_distance_process()
	
	if _set_invisible_timer:
		_leading_sprite.set_instance_shader_parameter("time_spread", time_spread - _time_buffer)
	
	_past_position = _get_pivot_node_position()
	
	# Quick and dirty fix, needs to be at the end of the frame so that sub processes know
	# to not run some logic (line 670)
	if _first_process_since_spawn:
		_first_process_since_spawn = false


func _get_pivot_node_position() -> Vector2:
	if DisplayServer.get_name() == "headless":
		return Vector2.ZERO
	
	return _snapshot_generator.get_target_position()


func _update_enabled(delta: float) -> void:
	var speed: float = _frame_speed / delta
	
	_is_enabled = (speed > speed_threshold) if automatic else enabled


func _on_enabled() -> void:
	# So that it starts right away without waiting
	_time_buffer = 0.0
	
	_distance_buffer = 0.0
	
	_stretch_past_position = _past_position
	
	if trail_type == TrailType.STRETCH:
		_snapshot_generator.queue_snapshot()
		
		_leading_sprite.visible = true
		
	elif single_snapshot:
		_snapshot_generator.queue_snapshot()


func _on_disabled() -> void:
	if emit_particle_on_disabled:
		if trail_type == TrailType.STRETCH and !_just_started:
			_emit_stretchy_particle(false)
		
		if trail_type == TrailType.GHOST:
			_emit_particle(_get_pivot_node_position(), _snapshot_generator._current_frame)
	
	_leading_sprite.visible = false


func _ghost_time_process(delta: float) -> void:
	_time_buffer -= delta
	
	if _time_buffer < 0.0:
		if !single_snapshot:
			_snapshot_generator.queue_snapshot()
		
		_emit_particle(_past_position, _snapshot_generator._current_frame)
		
		_time_buffer += time_spread * ceil(-_time_buffer / time_spread)


func _ghost_distance_process() -> void:
	_distance_buffer -= _frame_speed
	
	if _distance_buffer < 0.0:
		if !single_snapshot:
			_snapshot_generator.queue_snapshot()
		
		var direction: Vector2 = _frame_movement.normalized()
		
		var new_position: Vector2 = _past_position
		
		while _distance_buffer < 0.0:
			_emit_particle(new_position, _snapshot_generator._current_frame)
			
			_distance_buffer += distance_spread
			
			new_position += direction * distance_spread


func _stretch_time_process(delta: float) -> void:
	# Dirty fix of artifact that is caused when the trail spawns
	if _first_process_since_spawn:
		return
	
	_time_buffer -= delta
	
	if _time_buffer < 0.0:
		_emit_stretchy_particle()
		
		_time_buffer += time_spread * ceil(-_time_buffer / time_spread)


func _stretch_distance_process() -> void:
	_distance_buffer -= _frame_speed
	
	if _distance_buffer < 0.0:
		_emit_stretchy_particle()
		
		_distance_buffer += distance_spread * ceil(-_distance_buffer / distance_spread)


func _emit_stretchy_particle(emit_particle: bool = true) -> void:
	var offset: Vector2 = _stretch_past_position - _get_pivot_node_position()
	
	if emit_particle:
		_emit_particle(_get_pivot_node_position(), _snapshot_generator._current_frame + 1, offset)
	
	_clear_invisible_timer()
	
	_create_invisible_timer()
	
	_stretch_past_position = _get_pivot_node_position()
	
	if !single_snapshot:
		_snapshot_generator.queue_snapshot()


func _create_invisible_timer() -> void:
	_set_invisible_timer = get_tree().create_timer(trail_lifetime)


func _clear_invisible_timer() -> void:
	if _set_invisible_timer:
		for connection in _set_invisible_timer.timeout.get_connections():
			_set_invisible_timer.timeout.disconnect(connection.callable)
		
		_set_invisible_timer = null


func _emit_particle(in_position: Vector2, current_frame: float, stretch: Vector2 = Vector2.ZERO) -> void:
	_particle_emitter.emit_particle(
		Transform2D(0, in_position),
		Vector2(0, 0),
		Color.WHITE,
		Color(stretch.x, 0, current_frame, stretch.y),
		GPUParticles2D.EMIT_FLAG_POSITION | GPUParticles2D.EMIT_FLAG_CUSTOM
	)


func _sync_leading_sprite_visual() -> void:
	_leading_sprite.set_instance_shader_parameter("override_offset", (_stretch_past_position - _get_pivot_node_position()))
	
	_leading_sprite.set_instance_shader_parameter("override_current_frame", _snapshot_generator._current_frame)

#endregion
