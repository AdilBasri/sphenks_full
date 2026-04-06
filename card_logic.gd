extends Node3D

var card_type: String = "tetromino"
var is_in_hand: bool = false
var original_scale: Vector3

func _ready():
	original_scale = scale
	# Karta tıklanabilmesi için çalışma zamanında bir StaticBody3D ve CollisionShape3D ekleyelim
	var static_body = StaticBody3D.new()
	static_body.set_meta("is_card", true)
	static_body.set_meta("card_node", self)
	
	var collision_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	# Orjinal modelin boyutlarına göre yaklaşık bir hit-box oluşturuyoruz
	box_shape.size = Vector3(2.5, 0.05, 3.5) 
	collision_shape.shape = box_shape
	
	static_body.add_child(collision_shape)
	add_child(static_body)

func pick_up(camera: Camera3D):
	if is_in_hand: return
	is_in_hand = true
	
	var g_trans = global_transform
	get_parent().remove_child(self)
	camera.add_child(self)
	global_transform = g_trans
	
	# Tween animasyonu: kameranın altına gelsin ve dik dursun
	var tw = create_tween().set_parallel(true)
	var hand_pos = Vector3(0, -0.25, -0.5) # Ekranın alt ortası
	var hand_rot = Vector3(deg_to_rad(90), 0, 0) # Modele göre dikleşmesi için 90 derece döndürdük
	
	tw.tween_property(self, "position", hand_pos, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "rotation", hand_rot, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "scale", original_scale * 1.5, 0.4).set_trans(Tween.TRANS_SINE)
