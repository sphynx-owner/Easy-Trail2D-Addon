@tool
extends Object

static var instance: Object = Object.new()

# Static signal pattern
static var settings_changed_signal: Signal:
	get():
		if settings_changed_signal.is_null():
			instance.add_user_signal("settings_changed")
			settings_changed_signal = Signal(instance, "settings_changed")
		return settings_changed_signal

const KEY_PREFIX = "trail_generator"
const DEFAULT_TRAIL_LAYER_KEY = "%s/default_trail_layer" % KEY_PREFIX

## Fixed epsilon which a FixedAnimationPlayer would use to snap its fixed current position around events in an animation
static var default_trail_layer: int:
	get:
		return ProjectSettings.get_setting(DEFAULT_TRAIL_LAYER_KEY)

# Used to check if event_epsilon has been changed off of the ProjectSettings.setting_changed signal
static var _default_trail_layer_cache: int

static func setup():
	_setup_setting(
		DEFAULT_TRAIL_LAYER_KEY,
		2,
		{
			"type": TYPE_INT,
			"hint": PROPERTY_HINT_RANGE,
			"hint_string": "hint_range: 1, 20, 1",
		}
	)

	_default_trail_layer_cache = default_trail_layer
	
	ProjectSettings.settings_changed.connect(_on_project_settings_changed)


static func _setup_setting(key: String, default_value: Variant, config: Dictionary) -> void:
	if ProjectSettings.has_setting(key):
		return

	config.name = key

	ProjectSettings.set_setting(key, default_value)
	ProjectSettings.set_initial_value(key, default_value)
	ProjectSettings.add_property_info(config)


# I've added this so that not all animation players need to check this themselves.
# We keep the animation players' checks, however, in case any of them go out of sync.
static func _on_project_settings_changed():
	if _default_trail_layer_cache != default_trail_layer:
		settings_changed_signal.emit()
		_default_trail_layer_cache = default_trail_layer
