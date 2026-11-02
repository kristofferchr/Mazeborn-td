extends SceneTree
## Renders a scene for N frames and saves a PNG of the viewport.
## Usage: godot --path game -s res://tools/screenshot.gd -- <out.png> [scene] [frames]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://screenshot.png"
	var scene_path := args[1] if args.size() > 1 else "res://main.tscn"
	var frames := int(args[2]) if args.size() > 2 else 60
	root.add_child((load(scene_path) as PackedScene).instantiate())
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(out)
	print("screenshot: %s (%s)" % [out, error_string(err)])
	quit(err)
