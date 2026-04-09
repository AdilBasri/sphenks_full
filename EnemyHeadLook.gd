extends Skeleton3D

@export var bone_name: String = "mixamorig_Head"
@export var smooth_speed: float = 1.8
@export var max_yaw_degrees: float = 45.0
@export var max_pitch_degrees: float = 15.0

var bone_idx: int = -1
var camera: Camera3D
var initial_rotation: Quaternion
var current_rotation: Quaternion

func _ready():
	bone_idx = find_bone(bone_name)
	if bone_idx == -1:
		push_error("EnemyHeadLook: Bone '%s' not found!" % bone_name)
		set_process(false)
		return
		
	camera = get_viewport().get_camera_3d()
	
	# Store the initial pose rotation
	initial_rotation = get_bone_pose_rotation(bone_idx)
	current_rotation = initial_rotation

func _process(delta):
	if not camera or bone_idx == -1: return
	
	# Get target position in local skeleton space
	var target_global = camera.get("cursor_3d_pos")
	if target_global == null: 
		# If cursor pose is not available, look at player camera
		target_global = camera.global_position
	
	var target_local = to_local(target_global)
	
	# 1. Horizontal (Yaw) Calculation
	var dir_horizontal = Vector2(target_local.x, target_local.z).normalized()
	var yaw_angle = atan2(dir_horizontal.x, dir_horizontal.y) # Reversed for some Mixamo rigs? Let's use standard atan2(x, z)
	
	# In Godot, local Z is forward for bones usually, so atan2(x, z)
	yaw_angle = atan2(target_local.x, target_local.z)
	
	# 2. Vertical (Pitch) Calculation
	# Calculate pitch based on height difference and ground distance
	var ground_dist = Vector2(target_local.x, target_local.z).length()
	var pitch_angle = -atan2(target_local.y, ground_dist) # Negative to look up/down correctly
	
	# 3. Clamping
	yaw_angle = clamp(yaw_angle, deg_to_rad(-max_yaw_degrees), deg_to_rad(max_yaw_degrees))
	pitch_angle = clamp(pitch_angle, deg_to_rad(-max_pitch_degrees), deg_to_rad(max_pitch_degrees))
	
	# 4. Construct Target Rotation
	# We start from initial pose and apply our look offsets
	var yaw_quat = Quaternion(Vector3.UP, yaw_angle)
	var pitch_quat = Quaternion(Vector3.RIGHT, pitch_angle)
	
	# Combine rotations: Pitch (local X) then Yaw (local Y) relative to the initial pose
	var target_quat = initial_rotation * yaw_quat * pitch_quat
	
	# 5. Organic Smoothing (Slow Catch-up)
	current_rotation = current_rotation.slerp(target_quat, delta * smooth_speed)
	
	# Apply final pose
	set_bone_pose_rotation(bone_idx, current_rotation)
