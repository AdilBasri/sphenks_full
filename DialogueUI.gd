extends CanvasLayer

signal dialogue_finished

@onready var panel = $Control/Panel
@onready var text_label = $Control/Panel/RichTextLabel
@onready var continue_label = $Control/Panel/ContinueLabel
@onready var background_audio = $AudioStreamPlayer

var full_text: String = ""
var typing_speed: float = 0.0
var is_typing: bool = false
var audio_pitch_down: float = 0.33
var current_typing_id: int = 0

func _ready():
	visible = false
	continue_label.visible = false
	
	# Audio setup as requested
	var stream = load("res://Assets/Sounds/meaningless.mp3")
	if stream:
		background_audio.stream = stream
		background_audio.pitch_scale = audio_pitch_down
		# Loop is usually property of stream or handled here
		if stream is AudioStreamMP3: stream.loop = true

func display_text(dialogue: String):
	current_typing_id += 1
	var this_id = current_typing_id
	
	full_text = dialogue
	text_label.text = ""
	visible = true
	
	# Smooth fade-in
	$Control.modulate.a = 0
	var f_tw = create_tween()
	f_tw.tween_property($Control, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
	
	continue_label.visible = false
	is_typing = true
	
	background_audio.play()
	
	# Typewriter effect: complete full message in 3 seconds
	typing_speed = 3.0 / float(full_text.length()) if full_text.length() > 0 else 0
	
	var char_count = 0
	while char_count < full_text.length():
		if not is_typing or this_id != current_typing_id: break # Interrupted
		text_label.text += full_text[char_count]
		char_count += 1
		await get_tree().create_timer(typing_speed).timeout
	
	if this_id == current_typing_id:
		_on_typing_completed()

func _input(event):
	if not visible: return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_typing:
			# Instant completion
			is_typing = false
			text_label.text = full_text
			_on_typing_completed()
		elif continue_label.visible:
			# Smooth fade-out before closing
			var f_tw = create_tween()
			f_tw.tween_property($Control, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_SINE)
			await f_tw.finished
			
			visible = false
			background_audio.stop()
			dialogue_finished.emit()
		
		get_viewport().set_input_as_handled()

func _on_typing_completed():
	is_typing = false
	continue_label.visible = true
	background_audio.stop()
