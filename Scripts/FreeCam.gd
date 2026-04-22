extends Camera3D

@export var move_speed: float = 0.5
@export var boost_speed: float = 2.0
@export var mouse_sensitivity: float = 0.1
@export var zoom_speed: float = 0.75
@export var min_fov: float = 30.0

var is_active: bool = false
var yaw: float = 0.0
var pitch: float = 0.0
var default_fov: float = 80.0

func _ready():
	# Initially disabled
	process_mode = Node.PROCESS_MODE_ALWAYS # Still allow toggle during pause
	default_fov = fov
	set_enabled(false)

func set_enabled(enabled: bool):
	is_active = enabled
	set_process(enabled)
	set_process_input(enabled)
	
	if enabled:
		make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# Sync rotation
		yaw = rotation_degrees.y
		pitch = rotation_degrees.x
	else:
		# Return to game mouse mode
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		# Attempt to find the main camera to return to it
		var main_cam = get_tree().root.find_child("Camera3D", true, false)
		if main_cam and main_cam is Camera3D:
			main_cam.make_current()

func _input(event):
	if not is_active: return
	
	if event is InputEventMouseMotion:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, -89, 89)
		rotation_degrees = Vector3(pitch, yaw, 0)

func _process(delta):
	if not is_active: return
	
	var input_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input_dir.z -= 1
	if Input.is_key_pressed(KEY_S): input_dir.z += 1
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	if Input.is_key_pressed(KEY_Q): input_dir.y -= 1
	if Input.is_key_pressed(KEY_E): input_dir.y += 1
	
	var speed = move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed = boost_speed
		
	var forward = global_transform.basis.z.normalized()
	var right = global_transform.basis.x.normalized()
	var up = Vector3.UP
	
	var motion = (forward * input_dir.z + right * input_dir.x + up * input_dir.y).normalized()
	global_position += motion * speed * delta
	
	# Zoom logic (R key)
	var target_fov = min_fov if Input.is_key_pressed(KEY_R) else default_fov
	fov = lerp(fov, target_fov, delta * zoom_speed)
