extends CanvasLayer

@onready var sprite = $Sprite2D
var default_texture = preload("res://Assets/cursor/Cursor.png")

func _ready():
	# Ensure this layer is above everything else
	layer = 2000
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	process_mode = Node.PROCESS_MODE_ALWAYS # Run even during pause
	
	# Initial position to avoid frame 1 jump
	sprite.global_position = sprite.get_global_mouse_position()

func set_cursor_texture(tex: Texture2D):
	if tex:
		sprite.texture = tex
	else:
		sprite.texture = default_texture

func _process(_delta):
	# Update sprite position to follow mouse (using viewport coordinates for CanvasLayer)
	sprite.position = get_viewport().get_mouse_position()
	
	# Force hide hardware cursor if it becomes visible
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	# Toggle visibility based on mouse mode
	# Hide software cursor if mouse is captured (FPS mode)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		sprite.visible = false
	else:
		# Check if any other system wants to hide the default cursor
		var camera = get_viewport().get_camera_3d()
		if camera and camera.get("right_click_ui") and camera.right_click_ui.visible:
			sprite.visible = false
		else:
			sprite.visible = true
