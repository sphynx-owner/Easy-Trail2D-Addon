@tool
extends EditorPlugin

const Settings = preload("./settings.gd")

func _enter_tree() -> void:
	Settings.setup()
