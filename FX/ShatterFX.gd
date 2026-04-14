extends Node3D

@export var intensity: float = 1.0
@export var shard_count: int = 12 # Increased for premium feel
@export var piece_color: Color = Color(0.95, 0.95, 0.95)
@export var is_king_death: bool = false

var fluid_burst_scene = preload("res://FX/FluidBurst.tscn")
var base_shader = preload("res://Shaders/toon_ps1.gdshader")

func _ready():
	# 1. IMPACT HIT-STOP (Cinematic freeze) - ONLY FOR KING DEATH
	if is_king_death:
		_trigger_hit_stop()
	
	# 2. Spawn Surface Shockwave - ONLY FOR KING DEATH
	if is_king_death:
		_spawn_shockwave()
	
	# 3. Spawn Volumetric Dust Cloud (Match piece color)
	_spawn_dust_cloud()
	
	# 4. Spawn Premium Shards
	_spawn_premium_shards()
	
	# Self Cleanup (Real-time to avoid being stuck if time_scale is modified)
	get_tree().create_timer(1.8, true, false, true).timeout.connect(queue_free)

func _trigger_hit_stop():
	# Standard premium technique: freeze momentarily
	var old_scale = Engine.time_scale
	Engine.time_scale = 0.0
	# CRITICAL: Use process_always=true and ignore_time_scale=true or it will freeze FOREVER
	await get_tree().create_timer(0.06, true, false, true).timeout
	Engine.time_scale = old_scale

func _spawn_shockwave():
	# Using load() instead of preload() to ensure it works even if newly created
	var shock_ring_scene = load("res://FX/ShockRing.tscn")
	if not shock_ring_scene: return
	
	var ring = shock_ring_scene.instantiate()
	add_child(ring)
	ring.position.y = -0.01 # Slightly above table
	# Tint ring to match piece dust
	var ring_mesh = ring.get_node_or_null("Mesh")
	if ring_mesh:
		var mat = ring_mesh.mesh.material.duplicate()
		mat.albedo_color = piece_color * 0.8
		mat.albedo_color.a = 0.5
		ring_mesh.material_override = mat

func _spawn_dust_cloud():
	# Multiple bursts of varying grey levels based on piece color
	for i in range(3):
		var fluid = fluid_burst_scene.instantiate()
		var color_var = piece_color.darkened(randf_range(0.0, 0.3))
		fluid.amount = max(1, int(25 * intensity))
		add_child(fluid)
		
		var mat: ParticleProcessMaterial = fluid.process_material.duplicate()
		mat.color = color_var
		# Wider spread for the cloud
		mat.spread = 80.0
		fluid.process_material = mat
		fluid.emitting = true

func _spawn_premium_shards():
	var final_count = max(2, int(shard_count * intensity))
	
	# Create a shared material using the piece shader for consistency
	var shard_mat = ShaderMaterial.new()
	shard_mat.shader = base_shader
	shard_mat.set_shader_parameter("albedo_color", piece_color)
	shard_mat.set_shader_parameter("jitter_strength", 0.01) # Stable for fragments
	shard_mat.set_shader_parameter("color_steps", 4)
	shard_mat.set_shader_parameter("dither_grain", 0.4)
	
	for i in range(final_count):
		var shard = MeshInstance3D.new()
		
		# GEOMETRIC VARIETY: Mix of Boxes, Prisms (Pyramids), and Slices
		var dice = randf()
		if dice < 0.4:
			var box = BoxMesh.new()
			box.size = Vector3(randf_range(0.01, 0.03), randf_range(0.01, 0.05), randf_range(0.01, 0.03))
			shard.mesh = box
		elif dice < 0.8:
			var prism = PrismMesh.new()
			prism.size = Vector3(randf_range(0.02, 0.04), randf_range(0.02, 0.04), randf_range(0.01, 0.03))
			shard.mesh = prism
		else:
			# Long sliver
			var box = BoxMesh.new()
			box.size = Vector3(randf_range(0.005, 0.01), randf_range(0.05, 0.08), randf_range(0.005, 0.01))
			shard.mesh = box
		
		shard.material_override = shard_mat
		add_child(shard)
		
		var launch_dir = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(1.0, 2.0),
			randf_range(-1.0, 1.0)
		).normalized()
		
		var force = randf_range(0.4, 0.9)
		_animate_shard_premium(shard, launch_dir * force)

func _animate_shard_premium(shard: Node3D, velocity: Vector3):
	var tw = create_tween()
	var start_pos = shard.position
	var grav = 4.0
	var bounce_y = -0.02
	
	# Random tumble speed
	var rot_vel = Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))
	
	var anim_fn = func(t: float): 
		var y_offset = velocity.y * t - 0.5 * grav * t * t
		var x_offset = velocity.x * t
		var z_offset = velocity.z * t
		
		if y_offset < bounce_y and t < 0.8:
			velocity.y *= -0.3 # Less bounce, more heavy thud
			velocity.x *= 0.6
			velocity.z *= 0.6
			start_pos.y += y_offset - bounce_y
			y_offset = bounce_y 
			rot_vel *= 0.5 # Slow down rotation on bounce
		
		shard.position = start_pos + Vector3(x_offset, y_offset, z_offset)
		shard.rotate_x(rot_vel.x * 0.02)
		shard.rotate_y(rot_vel.y * 0.02)
		shard.rotate_z(rot_vel.z * 0.02)
	
	tw.parallel().tween_method(anim_fn, 0.0, 1.8, 1.8)
	tw.parallel().tween_property(shard, "scale", Vector3.ZERO, 0.5).set_delay(1.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
