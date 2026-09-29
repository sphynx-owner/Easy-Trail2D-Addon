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
@export var single_snapshot: bool = false:
	set(value):
		if single_snapshot == value:
			return
		
		_update_snapshot_generator()

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

@export_group("stretch settings", "stretch_")

## This would make it so that the _leading_sprite, which dynamically stretches
## with the subject also gets visually updated. It is mainly relevant for 
## elements that significantly change while they move, and it will 
## require running the snapshot generation each frame, so use carefully
@export var stretch_dynamic_trail_head: bool = true:
	set(value):
		if stretch_dynamic_trail_head == value:
			return
		
		stretch_dynamic_trail_head = value

@export var stretch_sample_count: int = 5:
	set(value):
		if stretch_sample_count == value:
			return
		
		stretch_sample_count = value
		
		_update_particles()

## The lifetime of the generated trail particles
@export var trail_lifetime: float = 1.0:
	set(value):
		if trail_lifetime == value:
			return
		
		trail_lifetime = value
		
		_update_particles()

@export_group("activation settings", "activate_")

## Setting this to `true` would let the trail generator enable
## itself automatically based on *activate_speed_threshold*
@export var activate_automatic: bool = true:
	set(value):
		if activate_automatic == value:
			return
		
		activate_automatic = value
		
		notify_property_list_changed()

## Define the speed threshold of the subject's movement
## in pixels per second for the trail generator to enable itself 
## when set to *activate_automatic*
@export var activate_speed_threshold: float = 0.0

## This is overridden if *activate_automatic* is true
@export var enabled: bool = true:
	set(value):
		if enabled == value:
			return
		
		enabled = value

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

## When enabled, you can manipulate [member look_direction],
## along side your movement of the character, and the result
## will be an intuitive sorting of the trail around your target.
## If you are moving upwards, the trail will be sorted on top of
## the target. If downwards, under. 
## The look direction will determine the sorting of the trail when
## moving perfectly horizontally. If facing downwards, the trail
## will be sorted below the target, and vice versa.
@export var movement_look_direction_sort: bool = false

@export_group("spread settings", "spread_")

## Whether the trail generates based on distance traveled 
## or based on constant time intervals.
## It is export storage on purpose, so that it can appear in the
## correct place in the property list between custom properties
@export var spread_mode: SpreadMode = SpreadMode.TIME:
	set(value):
		if spread_mode == value:
			return
		
		spread_mode = value
		
		notify_property_list_changed()
		
		_update_snapshot_generator()

## How far (in global units) does the element have to travel to generate 
## a trail particle, teleportation over large distances is supported to spread
## trail particles evenly.
@export var spread_distance_interval: float = 25.0

## The minimum amount of desired separate sanpshot frames to use 
## when generating the trail. This would let you save past visuals of the 
## element. 
## Does not indicate final allocated frames count, but guarantees a minimum.
## When sperad mode is set to TIME, it is determined automatically, 
## But when spreading trail particles based on distance, a new snapshot
## can be required potentially every frame, making it impossible to activate_automatically
## determine.
@export var snapshots_stored_limit: int = 16:
	set(value):
		if snapshots_stored_limit == value:
			return
		
		snapshots_stored_limit = value
		
		_update_snapshot_generator()
		
		_update_particles()

## The time intervals between trail particle generation when the trail generator is enabled.
## When spread_mode is set to TIME, it also affects the reserved frame count of the snapshot generator
## as more concurrent past snapshots require more texture storage.
@export var spread_time_interval: float = 0.1:
	set(value):
		if spread_time_interval == value:
			return
		
		spread_time_interval = value
		
		_update_snapshot_generator()
		
		_update_particles()

@export_storage var snapshots_refresh_rate: int = 15

@export_group("particle emitter", "particles_")

@export var particles_amount: int = 25:
	set(value):
		if particles_amount == value:
			return
		
		particles_amount = value
		
		_update_particles()

@export var particles_fixed_fps: int = 60:
	set(value):
		if particles_fixed_fps == value:
			return
		
		particles_fixed_fps = value
		
		_update_particles()

@export var particles_visibility_rect: Rect2 = Rect2(-500, -500, 1000, 1000):
	set(value):
		if particles_visibility_rect == value:
			return
		
		particles_visibility_rect = value
		
		_update_particles()

## Use this in conjunction with [member movement_look_direction_sort] to 
## determine the sorting of the trail relatively to the target when moving
## horizontally.
var look_direction: Vector2

## Automatically being set taking 'enabled' and 'activate_automatic' into account
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

## The snapshot generator wrapped by this trail generator.
## It is in charge of managing snapshot atlases of the targets
var _snapshot_generator: SnapshotGenerator

## The particle emitter wrapped by this trail generator.
## It spawns particles that display the snapshots and activate_automatically
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

var _first_process: bool = true


#region Virtual Methods

func _init() -> void:
	if DisplayServer.get_name() == "headless":
		return
	
	texture_filter = TEXTURE_FILTER_NEAREST
	
	process_priority = 1
	
	_snapshot_generator = SnapshotGenerator.new()


func _validate_property(property: Dictionary) -> void:
	if property.name in ["stretch_dynamic_trail_head", "stretch_sample_count", "stretch settings"]:
		if trail_type != TrailType.STRETCH:
			property.usage &= ~PROPERTY_USAGE_EDITOR
	
	if property.name in ["enabled"]:
		if activate_automatic:
			property.usage &= ~PROPERTY_USAGE_EDITOR


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	
	if Engine.is_editor_hint():
		var new_gizmo: SnapshotRectGizmo = SnapshotRectGizmo.new()
		
		new_gizmo.node = self
		
		new_gizmo.top_level = true
		
		add_child(new_gizmo)
	
	_snapshot_generator.process_priority = process_priority + 1
	
	add_child(_snapshot_generator)
	
	# We put this after add_child() so that it will have the _sub_viewport children,
	# which it adds itself off its _ready(), by then.
	_update_snapshot_generator()
	
	if !material:
		material = DEFAULT_CANVAS_GROUP_MATERIAL.duplicate()
	
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	
	_update_canvas_group()
	
	_particle_emitter = GPUParticles2D.new()
	
	_particle_emitter.emitting = false
	
	_particle_emitter.interpolate = false
	
	_particle_emitter.process_material = DEFAULT_TRAIL_PROCESS_MATERIAL
	
	_particle_emitter.material = DEFAULT_TRAIL_PARTICLE_MATERIAL
	
	_particle_emitter.texture = _snapshot_generator.atlas_texture_2d
	
	_particle_emitter.visibility_rect = Rect2(-100000, -100000, 200000, 200000)
	
	_particle_emitter.local_coords = false
	
	_particle_emitter.draw_order = GPUParticles2D.DRAW_ORDER_INDEX
	
	_particle_emitter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	_particle_emitter.process_priority = process_priority + 1
	
	add_child(_particle_emitter)
	
	_leading_sprite = Sprite2D.new()
	
	_leading_sprite.texture = _snapshot_generator.atlas_texture_2d
	
	_leading_sprite.material = DEFAULT_TRAIL_PARTICLE_MATERIAL
	
	_leading_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	
	_leading_sprite.set_instance_shader_parameter("manual", true)
	
	_leading_sprite.visible = false
	
	add_child(_leading_sprite)
	
	_update_particles()


func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	
	if !pivot_node:
		return
	
	if _first_process:
		_first_process = false
		
		_current_position = get_pivot_position()
		
		_current_time = _get_time()
		
		_past_position = _current_position
		
		_past_time = _current_time
	
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
	
	_is_enabled = (speed > activate_speed_threshold) if activate_automatic else enabled
	
	if _is_enabled:
		match spread_mode:
			SpreadMode.TIME:
				_time_spread_process(delta)
			
			SpreadMode.DISTANCE:
				_distance_spread_process(_frame_movement)
		
		if trail_type == TrailType.STRETCH:
			if stretch_dynamic_trail_head:
				_snapshot_generator.queue_snapshot(false)
			
			_update_leading_sprite()
	
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


func _update_snapshot_generator() -> void:
	if !_snapshot_generator:
		return
	
	_snapshot_generator.pivot_node = pivot_node
	
	_snapshot_generator.targets = targets
	
	_snapshot_generator.snapshot_rect = snapshot_rect
	
	_snapshot_generator.snapshot_resolution_scale = snapshot_resolution_scale
	
	var min_snapshot_count: int
	
	if single_snapshot:
		min_snapshot_count = 1
		
	else:
		match spread_mode:
			SpreadMode.DISTANCE:
				min_snapshot_count = snapshots_stored_limit
			
			SpreadMode.TIME:
				min_snapshot_count = min(ceil(trail_lifetime / spread_time_interval) + 1, snapshots_stored_limit)
	
	# It is easiest to simply create the smallest square atlas to contain the required 
	# reserved frames count.
	var dimension: int = ceil(sqrt(min_snapshot_count))
	
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
	
	_particle_emitter.amount = particles_amount
	
	_particle_emitter.fixed_fps = particles_fixed_fps
	
	_particle_emitter.visibility_rect = particles_visibility_rect
	
	_particle_emitter.set_instance_shader_parameter("atlas_h_frames", _snapshot_generator.atlas_dimensions.x)
	
	_particle_emitter.set_instance_shader_parameter("atlas_v_frames", _snapshot_generator.atlas_dimensions.y)
	
	_particle_emitter.set_instance_shader_parameter("snapshot_resolution_scale", snapshot_resolution_scale)
	
	_particle_emitter.set_instance_shader_parameter("sample_count", stretch_sample_count)
	
	_leading_sprite.set_instance_shader_parameter("atlas_h_frames", _snapshot_generator.atlas_dimensions.x)
	
	_leading_sprite.set_instance_shader_parameter("atlas_v_frames", _snapshot_generator.atlas_dimensions.y)
	
	_leading_sprite.set_instance_shader_parameter("snapshot_resolution_scale", snapshot_resolution_scale)
	
	_leading_sprite.set_instance_shader_parameter("sample_count", stretch_sample_count)


func get_pivot_position() -> Vector2:
	if DisplayServer.get_name() == "headless":
		return Vector2.ZERO
	
	return _snapshot_generator.get_pivot_position()


func _get_time() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_enabled() -> void:
	if single_snapshot:
		_snapshot_generator.queue_snapshot(false)
		
	else:
		_snapshot_generator.queue_snapshot()
	
	_last_emit_time = _past_time
	_last_emit_position = _past_position
	
	_time_buffer = spread_time_interval if trail_type == TrailType.GHOST else 0.0
	
	_distance_buffer = spread_distance_interval if trail_type == TrailType.GHOST else 0.0


func _on_disabled() -> void:
	if _last_emit_position != _past_position and trail_type == TrailType.STRETCH:
		_emit_stretchy_particle(_current_position, -1)
	
	_leading_sprite.visible = false


func _time_spread_process(delta: float) -> void:
	_time_buffer += delta
	
	if _time_buffer > spread_time_interval:
		if !single_snapshot:
			_snapshot_generator.queue_snapshot()
		
		match trail_type:
			TrailType.GHOST:
				_emit_particle(_past_position)
			
			TrailType.STRETCH:
				_emit_stretchy_particle(_current_position, -1 if !stretch_dynamic_trail_head else 0)
		
		_time_buffer = fmod(_time_buffer, spread_time_interval)


func _distance_spread_process(delta: Vector2) -> void:
	var speed: float = delta.length()
	
	_distance_buffer += speed
	
	if _distance_buffer > spread_distance_interval:
		if !single_snapshot:
			_snapshot_generator.queue_snapshot()
		
		var starting_distance: float = spread_distance_interval - (_distance_buffer - speed)
		
		var direction: Vector2 = delta.normalized()
		
		var emit_position: Vector2 = _past_position + direction * starting_distance
		
		for i in int(_distance_buffer / spread_distance_interval):
			match trail_type:
				TrailType.GHOST:
					_emit_particle(emit_position)
				
				TrailType.STRETCH:
					_emit_stretchy_particle(emit_position, -1 if !stretch_dynamic_trail_head else 0)
			
			emit_position += direction * spread_distance_interval
		
		_distance_buffer = fmod(_distance_buffer, spread_distance_interval)


func _emit_stretchy_particle(p_position: Vector2, frame_offset: int = 0) -> void:
	var stretch: Vector2 = _last_emit_position - p_position
	
	var particle_stretch_time: float = _current_time - _last_emit_time
	
	_emit_particle(p_position, frame_offset, stretch, particle_stretch_time)
	
	_last_emit_position = p_position
	
	_last_emit_time = _current_time


func _emit_particle(
	p_position: Vector2,
	frame_offset: int = 0,
	stretch: Vector2 = Vector2.ZERO,
	stretch_time: float = 0.0
) -> void:
	_particle_emitter.emit_particle(
		Transform2D(0, p_position + Vector2(snapshot_rect.get_center())),
		Vector2(),
		Color(stretch_time, _snapshot_generator.get_current_frame(frame_offset), 0, 1.0),
		# HACK @sphynx-owner: we reserve the green channel for the age of the particle, 
		Color(stretch.x, 0, stretch.y, trail_lifetime),
		GPUParticles2D.EMIT_FLAG_POSITION | GPUParticles2D.EMIT_FLAG_CUSTOM | GPUParticles2D.EMIT_FLAG_COLOR
	)


func _update_leading_sprite() -> void:
	_leading_sprite.global_position = get_pivot_position() + Vector2(snapshot_rect.get_center())
	
	_leading_sprite.visible = trail_type == TrailType.STRETCH and _last_emit_position != _current_position
	
	_leading_sprite.set_instance_shader_parameter("manual", true)
	_leading_sprite.set_instance_shader_parameter("manual_atlas_frame", _snapshot_generator.get_future_latest_frame(-1) if !stretch_dynamic_trail_head else _snapshot_generator.get_current_frame())
	_leading_sprite.set_instance_shader_parameter("manual_stretch_offset", _last_emit_position - _current_position)
	_leading_sprite.set_instance_shader_parameter("manual_stretch_time", _current_time - _last_emit_time)
	_leading_sprite.set_instance_shader_parameter("manual_age", 0)
	_leading_sprite.set_instance_shader_parameter("manual_lifespan", trail_lifetime)

#endregion
