@tool
class_name TrailGenerator
extends CanvasGroup
## This class provides easy tools to generate visually accurate and dynamic 
## trails for existing elements, while staying performant and resource efficient

const DEFAULT_CANVAS_GROUP_MATERIAL: Material = \
preload("res://addons/easy-trail-2d/materials/trail_canvas_group_material.tres")

const DEFAULT_TRAIL_PROCESS_MATERIAL: Material = \
preload("res://addons/easy-trail-2d/materials/trail_emitter_material.tres")

const DEFAULT_TRAIL_PARTICLE_MATERIAL: Material = \
preload("res://addons/easy-trail-2d/materials/trail_particle_material.tres")

# The threshold, in degrees above the horizontal line, 
# which classify the normalized movement direction as non-horizontal.
const VERTICAL_SPEED_THRESHOLD: float = cos(deg_to_rad(15))

enum TrailType {STRETCH, GHOST}

enum SpreadMode {DISTANCE, TIME}


## The list of nodes that will be captured and have trail generated for
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

@export_group("snapshot settings", "snapshot_")

## The global rect within which we capture the elements.
## You can improve the resolution independently with [member snapshot_resolution_scale]
@export var snapshot_rect: Rect2i = Rect2i(-128, -128, 256, 256):
	set(value):
		if snapshot_rect == value:
			return
		
		snapshot_rect = value
		
		_update_snapshot_generator()
		
		_update_particles()

## This can be used to increase the quality of the trail snapshots, 
## will not affect the snapshot_rect size
@export var snapshot_resolution_scale: float = 1.0:
	set(value):
		if snapshot_resolution_scale == value:
			return
		
		snapshot_resolution_scale = value
		
		_update_snapshot_generator()
		
		_update_particles()

## Force only one snapshot to be stored, any updates will affect
## all particles as a result.
@export var snapshot_single: bool = false:
	set(value):
		if snapshot_single == value:
			return
		
		snapshot_single = value
		
		_update_snapshot_generator()
		
		_update_particles()

@export_group("trail settings", "trail_")

## When set to [code]TrailType.GHOST[/code], generates discrete ghost particles at 
## past positions. When set to [code]TrailType.STRETCH[/code], generates stretched particles that bridge between 
## past and current position
@export var trail_type: TrailType = TrailType.STRETCH:
	set(value):
		if trail_type == value:
			return
		
		trail_type = value
		
		notify_property_list_changed()
		
		_update_particles()

## The lifetime of trail particles
@export var trail_lifetime: float = 1.0:
	set(value):
		if trail_lifetime == value:
			return
		
		trail_lifetime = value
		
		_update_snapshot_generator()
		
		_update_particles()

## The texture to be used for the particle's color
@export var trail_texture: Texture2D:
	set(value):
		if trail_texture == value:
			return
		
		trail_texture = value
		
		_update_canvas_group()

## Controls the alpha of the particle over time, can be used
## for decay and more.
@export var trail_alpha_texture: Texture2D:
	set(value):
		if trail_alpha_texture == value:
			return
		
		trail_alpha_texture = value
		
		_update_canvas_group()

## A limit on how many separate snapshots can be taken over time.
@export var trail_max_refresh_rate: int = 15:
	set(value):
		if trail_max_refresh_rate == value:
			return
		
		trail_max_refresh_rate = value
		
		_update_snapshot_generator()
		
		_update_particles()

## The resulting size of snapshots storage. Used to determine the snapshot atlas size. It is affected
## by [member trail_max_refresh_rate], [member trail_lifetime] and for the time spread mode also [member spread_time_interval].
## [b]Please set those carefully[/b]. Set too high and they will result in a very large atlas texture, increasing VRAM usage
## and potentially crashing.
@export_custom(0, "TYPE_INT", PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY) var trail_snapshot_store_size: int

@export_group("stretch settings", "stretch_")

## As the targets move, a sprite controlled by the generator dynamically stretches to it
## to fill in the gap from the last particle. When the spread interval is reached, it's seamlessly replaced
## with an actual static particle. When this property is set to [code]true[/code], that dynamically stretched sprite would
## also consinuously update the snapshot it displays to more tightly fit the subjects.
@export var stretch_dynamic_trail_head: bool = true:
	set(value):
		if stretch_dynamic_trail_head == value:
			return
		
		stretch_dynamic_trail_head = value

## Stretching sprite images is not free, and requires iteration on the shader.
## The higher the count, the more solid the stretched result would be. The lower the count,
## the easier it would be for the stretched particles to miss thin details and lose opacity.
## The effect also depends on the stretch distance, so it can also be combatted with lower
## spread intervals.
@export var stretch_sample_count: int = 5:
	set(value):
		if stretch_sample_count == value:
			return
		
		stretch_sample_count = value
		
		_update_particles()

@export_group("ghost settings", "ghost_")

@export var ghost_unique_color_count: int = 10

@export var ghost_randomize_colors: bool = false

@export_group("activation settings", "activate_")

## When [code]true[/code] the trail would activate automatically based on the movement speed
## of [member pivot_node] compared against [member activate_speed_threshold]
@export var activate_automatic: bool = true:
	set(value):
		if activate_automatic == value:
			return
		
		activate_automatic = value
		
		notify_property_list_changed()

## When [member activate_automatic] is [code]true[/code], this value would be used to check
## the [member pivot_node] against to enable the trail automatically.
@export var activate_speed_threshold: float = 0.0

## Works regardless of [member activate_automatic]. When set to non-negative value, would [b]deactivate[/b]
## the trail during any single-frame teleportation of a distance that's larger than the threshold.
@export var activate_teleport_threshold: float = -1.0

## When [member activate_automatic] is [code]false[/code], use this value to manually enable
## and disable the trail generator yourself.
@export var enabled: bool = true:
	set(value):
		if enabled == value:
			return
		
		enabled = value

@export_group("spread settings", "spread_")

## Whether the trail generates based on distance traveled 
## or based on constant time intervals.
## It is export storage on purpose, so that it can appear in the
## correct place in the property list between custom properties
@export var spread_mode: SpreadMode = SpreadMode.DISTANCE:
	set(value):
		if spread_mode == value:
			return
		
		spread_mode = value
		
		notify_property_list_changed()
		
		_update_snapshot_generator()
		
		_update_particles()

## How far (in global units) does the element have to travel to generate 
## a trail particle, teleportation over large distances is supported to spread
## trail particles evenly.
@export var spread_distance_interval: float = 50.0

## The time intervals between trail particle generation when the trail generator is enabled.
## When spread_mode is set to TIME, it also affects the reserved frame count of the snapshot generator
## as more concurrent past snapshots require more texture storage.
@export var spread_time_interval: float = 0.2:
	set(value):
		if spread_time_interval == value:
			return
		
		spread_time_interval = value
		
		_update_snapshot_generator()
		
		_update_particles()

@export_group("particle emitter", "particles_")

## Controls the amount of particles managed by the particle emitter, see [member GPUParticles2D.amount]
@export var particles_amount: int = 300:
	set(value):
		if particles_amount == value:
			return
		
		particles_amount = value
		
		_update_particles()

## Controls the refresh rate of particles managed by the particle emitter, see [member GPUParticles2D.fixed_fps]
@export var particles_fixed_fps: int = 60:
	set(value):
		if particles_fixed_fps == value:
			return
		
		particles_fixed_fps = value
		
		_update_particles()

## Controls the visibility rect of the particle emitter, see [member GPUParticles2D.visibility_rect]
@export var particles_visibility_rect: Rect2 = Rect2(-5000, -5000, 10000, 10000):
	set(value):
		if particles_visibility_rect == value:
			return
		
		particles_visibility_rect = value
		
		_update_particles()

@export_group("sort settings", "sort_")

## When [code]ture[/code] you can manipulate [member sort_look_direction],
## along side the movement of the character, and the result
## will be an intuitive sorting of the trail around your target.
## If you are moving upwards, the trail will be sorted on top of
## the target. If downwards, under. 
## The look direction will determine the sorting of the trail when
## moving perfectly horizontally. If facing downwards, the trail
## will be sorted below the target, and vice versa.
@export var sort_by_movement_and_look_direction: bool = false

## Use this in conjunction with [member sort_by_movement_and_look_direction] to 
## determine the sorting of the trail relatively to the target when moving
## horizontally.
@export var sort_look_direction: Vector2

## Automatically set, use [member activate_automatic] and [member enable] instaed
var _is_enabled: bool = false:
	set(value):
		if value == _is_enabled:
			return
		
		_is_enabled = value
		
		if _is_enabled:
			_on_enabled()
			
		else:
			_on_disabled()

## The snapshot generator that's spawned and managed by this trail generator.
## It is in charge of generating and managing snapshot atlases of the targets
var _snapshot_generator: SnapshotGenerator

## The particle emitter that's spawned and managed by this trail generator.
## It spawns particles that display snapshots and behave over time.
var _particle_emitter: GPUParticles2D

## A sprite that dynamically stretches to the [member pivot_node] and is used 
## for seamless generation of stretched particles.
var _leading_sprite: Sprite2D

## Used for particle generation, and automatic activation.
var _current_position: Vector2

## Used for particle generation, and automatic activation.
var _past_position: Vector2

## Used to connect between stretched particles.
var _last_emit_position: Vector2

## When genreating stretchy particles, used to let the particle know
## over how long of a period was it being stretched for before it was actually spawned.
var _current_time: float = 0.0

## When genreating stretchy particles, used to let the particle know
## over how long of a period was it being stretched for before it was actually spawned.
var _past_time: float = 0.0

## Used for time-based spreading of particles
var _time_buffer: float = 0.0

## When genreating stretchy particles, used to let the particle know
## over how long of a period was it being stretched for before it was actually spawned.
var _last_emit_time: float = 0.0

## Used for distance-based spreading of particles
var _distance_buffer: float = 0.0

## Used for the initial process of the trail generator to prevent artifacts and glitches at spawn.
var _first_process: bool = true

var _refresh_rate_time_buffer: float = 0.0

var _can_update_snapshots: bool = false

var _snapshot_updated: bool = false

var _particle_counter:int = 0

#region Virtual Methods

func _init() -> void:
	if DisplayServer.get_name() == "headless":
		return
	
	process_priority = 1
	
	_snapshot_generator = SnapshotGenerator.new()


func _validate_property(property: Dictionary) -> void:
	var should_hide_property: bool = false
	
	if property.name in ["stretch_dynamic_trail_head", "stretch_sample_count", "stretch settings"]:
		if trail_type != TrailType.STRETCH:
			should_hide_property = true
		
	elif property.name in ["ghost_unique_color_count", "ghost_randomize_colors", "ghost settings"]:
		if trail_type != TrailType.GHOST:
			should_hide_property = true
		
	elif property.name in ["enabled"]:
		if activate_automatic:
			should_hide_property = true
		
	elif property.name in ["spread_distance_interval"]:
		should_hide_property = spread_mode == SpreadMode.TIME
		
	elif property.name in ["spread_time_interval"]:
		should_hide_property = spread_mode != SpreadMode.TIME
		
	elif property.name in ["snapshot_store_size"]:
		if snapshot_single:
			should_hide_property = true
		
	elif property.name in ["sort_look_direction"]:
		if !sort_by_movement_and_look_direction:
			should_hide_property = true
	
	if should_hide_property:
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
	
	# TODO @sphynx-owner: figure out if necessary
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
	
	global_position = _current_position
	
	_current_time = _get_time()
	
	var _frame_movement: Vector2 = _current_position - _past_position
	
	var _frame_speed: float = _frame_movement.length()
	
	if sort_by_movement_and_look_direction:
		var normalized_velocity: Vector2 = _frame_movement.normalized()
		
		var is_horizontal: bool = abs(normalized_velocity.x) > VERTICAL_SPEED_THRESHOLD
		
		var target_z_index: int = pivot_node.z_index
		
		if is_horizontal:
			z_index = target_z_index + (1 if sort_look_direction.y < 0 else -1)
			
		else:
			z_index = target_z_index + (1 if normalized_velocity.y < 0 else -1)
	
	var speed: float = _frame_speed / delta
	
	_refresh_rate_time_buffer += delta
	
	if _refresh_rate_time_buffer > (1.0 / trail_max_refresh_rate):
		_refresh_rate_time_buffer = 0.0
		_can_update_snapshots = true
	
	var _temp_current_position: Vector2 = _current_position
	
	var teleported_too_far: bool = activate_teleport_threshold >= 0.0 and _frame_speed > activate_teleport_threshold
	
	# HACK @sphynx-owner: When the trail is disabled a stretchy particle may be placed
	# to fill in the gap or replace the leading sprite. However if we want to stub that
	# behavior when the teleportation is too large, we can do so by simply overriding
	# the _current_position temporarily for that logic to happen.
	if teleported_too_far:
		_current_position = _past_position
	
	_is_enabled = !teleported_too_far and ((speed > activate_speed_threshold) if activate_automatic else enabled)
	
	# HACK @sphynx-owner: we need to set the _current position back otherwise it will get stuck at 
	# being considered teleporting too far and enter a loop.
	if teleported_too_far:
		_current_position = _temp_current_position
	
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
	
	if _snapshot_updated:
		_can_update_snapshots = false
		_snapshot_updated = false

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
	
	var desired_snapshot_count: int
	
	if snapshot_single:
		desired_snapshot_count = 1
		
	else:
		match spread_mode:
			SpreadMode.DISTANCE:
				desired_snapshot_count = int(trail_lifetime * trail_max_refresh_rate) + 1
			
			SpreadMode.TIME:
				desired_snapshot_count = min(int(trail_lifetime / spread_time_interval) + 1, int(trail_lifetime * trail_max_refresh_rate) + 1)
	
	var atlas_dimensions: Vector2i = _get_smallest_circumference_rectangle(desired_snapshot_count)
	
	_snapshot_generator.atlas_dimensions = atlas_dimensions
	
	trail_snapshot_store_size = atlas_dimensions.x * atlas_dimensions.y


func _update_canvas_group() -> void:
	if !material:
		return
	
	material.set_shader_parameter("trail_texture", trail_texture)
	material.set_shader_parameter("alpha_texture", trail_alpha_texture)


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
	_snapshot_generator.queue_snapshot()
	
	_last_emit_time = _past_time
	_last_emit_position = _past_position
	
	_time_buffer = spread_time_interval if trail_type == TrailType.GHOST else 0.0
	
	_distance_buffer = spread_distance_interval if trail_type == TrailType.GHOST else 0.0


func _on_disabled() -> void:
	if _last_emit_position != _past_position and trail_type == TrailType.STRETCH:
		if stretch_dynamic_trail_head:
			_snapshot_generator.queue_snapshot()
		
		_emit_stretchy_particle(_current_position, _snapshot_generator.get_latest_frame())
	
	_leading_sprite.visible = false


func _time_spread_process(delta: float) -> void:
	_time_buffer += delta
	
	if _time_buffer > spread_time_interval:
		if stretch_dynamic_trail_head and _can_update_snapshots:
			_snapshot_generator.queue_snapshot()
			_snapshot_updated = true
		
		match trail_type:
			TrailType.GHOST:
				_emit_particle(_past_position, _snapshot_generator.get_latest_frame())
			
			TrailType.STRETCH:
				_emit_stretchy_particle(_past_position, _snapshot_generator.get_latest_frame())
		
		if !stretch_dynamic_trail_head and _can_update_snapshots:
			_snapshot_generator.queue_snapshot()
			_snapshot_updated = true
		
		_time_buffer = fmod(_time_buffer, spread_time_interval)


func _distance_spread_process(delta: Vector2) -> void:
	var speed: float = delta.length()
	
	_distance_buffer += speed
	
	if _distance_buffer > spread_distance_interval:
		if stretch_dynamic_trail_head and _can_update_snapshots:
			_snapshot_generator.queue_snapshot()
			_snapshot_updated = true
		
		var starting_distance: float = spread_distance_interval - (_distance_buffer - speed)
		
		var direction: Vector2 = delta.normalized()
		
		var emit_position: Vector2 = _past_position + direction * starting_distance
		
		for i in int(_distance_buffer / spread_distance_interval):
			match trail_type:
				TrailType.GHOST:
					_emit_particle(emit_position, _snapshot_generator.get_latest_frame())
				
				TrailType.STRETCH:
					_emit_stretchy_particle(emit_position, _snapshot_generator.get_latest_frame())
			
			emit_position += direction * spread_distance_interval
		
		if !stretch_dynamic_trail_head and _can_update_snapshots:
			_snapshot_generator.queue_snapshot()
			_snapshot_updated = true
		
		_distance_buffer = fmod(_distance_buffer, spread_distance_interval)


func _emit_stretchy_particle(p_position: Vector2, atlas_frame: int) -> void:
	var stretch: Vector2 = _last_emit_position - p_position
	
	var particle_stretch_time: float = _current_time - _last_emit_time
	
	_emit_particle(p_position, atlas_frame, stretch, particle_stretch_time)
	
	_last_emit_position = p_position
	
	_last_emit_time = _current_time


func _emit_particle(
	p_position: Vector2,
	atlas_frame: int,
	stretch: Vector2 = Vector2.ZERO,
	stretch_time: float = 0.0
) -> void:
	_particle_emitter.emit_particle(
		Transform2D(0, p_position + Vector2(snapshot_rect.get_center())),
		Vector2(),
		Color(
			stretch_time,
			atlas_frame,
			fmod(randi_range(0, ghost_unique_color_count - 1) if ghost_randomize_colors else _particle_counter,
			ghost_unique_color_count) / ghost_unique_color_count, 1.0
		),
		# HACK @sphynx-owner: we reserve the green channel for the age of the particle, 
		Color(stretch.x, 0, stretch.y, trail_lifetime),
		GPUParticles2D.EMIT_FLAG_POSITION | GPUParticles2D.EMIT_FLAG_CUSTOM | GPUParticles2D.EMIT_FLAG_COLOR
	)
	
	_particle_counter += 1


func _update_leading_sprite() -> void:
	_leading_sprite.global_position = get_pivot_position() + Vector2(snapshot_rect.get_center())
	
	_leading_sprite.visible = trail_type == TrailType.STRETCH and _last_emit_position != _current_position and _is_enabled
	
	_leading_sprite.set_instance_shader_parameter("manual", true)
	_leading_sprite.set_instance_shader_parameter("manual_atlas_frame", _snapshot_generator.get_naive_current_frame() if stretch_dynamic_trail_head else _snapshot_generator.get_latest_frame())
	_leading_sprite.set_instance_shader_parameter("manual_stretch_offset", _last_emit_position - _current_position)
	_leading_sprite.set_instance_shader_parameter("manual_stretch_time", _current_time - _last_emit_time)
	_leading_sprite.set_instance_shader_parameter("manual_age", 0)
	_leading_sprite.set_instance_shader_parameter("manual_lifespan", trail_lifetime)


## Derived myself. Could be directly copied from somewhere.
func _get_smallest_circumference_rectangle(number: int) -> Vector2i:
	var root: int = ceil(sqrt(number))
	
	var lenience: int = 0
	
	while root > 0:
		@warning_ignore("integer_division")
		var root_2: int = (number - 1) / root + 1
		
		var result: int = root * root_2 - number
		
		if result >= 0 and result <= lenience:
			return Vector2(root_2, root)
		
		root -= 1
		
		# +2 seemed to work better for smaller numbers (24 resulting in 6 and 4 instead of 3 and 8 with +1)
		lenience += 2
	
	push_error("count not find smallest circumference rectangle")
	return Vector2(-1, -1)

#endregion
