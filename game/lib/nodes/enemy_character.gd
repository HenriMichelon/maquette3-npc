class_name EnemyCharacter extends CharacterBody3D

const ANIM_IDLE = "idle"
const ANIM_WALK = "walk"
const ANIM_RUN = "run"
const ANIM_ATTACK = "attack"
const ANIM_DIE = "die"
const ANIM_HIT = "hit"

@export var label:String = "Enemy"
@export var hear_distance:float = 5
@export var attack_distance:float = 0.9
@export var height:float = 0.0

@onready var weapon:ItemWeapon = $RootNode/Skeleton3D/WeaponAttachement/Weapon
@onready var hit_points_roll:DicesRoll = $HitPoints
@onready var walking_speed_roll:DicesRoll = $WalkingSpeed
@onready var running_speed_roll:DicesRoll = $RunningSpeed
@onready var detection_distance_roll:DicesRoll = $DetectionDistance
@onready var help_distance_roll:DicesRoll = $HelpDistance

@onready var anim_tree:AnimationTree = $AnimationTree
@onready var collision_shape:CollisionShape3D = $CollisionShape3D

var anim_state:AnimationNodeStateMachinePlayback
var label_info:Label
var progress_hp:ProgressBar
var raycast_detection:RayCast3D

var info_distance:float = 25

var xp:int
var anim_die_name:String
var in_info_area:bool = false
var timer_attack:Timer
var timer_start_animation:Timer
# action animation playing
var attack_cooldown:bool = false
# one hit only allowed during attack cooldown
var hit_allowed:bool = false
# player detection position
var detected_position:Vector3 = Vector3.ZERO
var move_to_detected_position:bool = false
var previous_position:Vector3 = Vector3.ZERO

var hit_points:int = 100
var walking_speed:float = 0.5
var running_speed:float = 1.0
var detection_distance:float = 10
var help_distance:float = 15
var help_called:bool = false
var idle_rotation_tween:Tween

func _ready():
	weapon.disable()
	weapon.use_area.set_collision_mask_value(Consts.LAYER_PLAYER, true)
	weapon.use_area.set_collision_mask_value(Consts.LAYER_ENEMY_CHARACTER, false)
	connect("input_event", _on_input_event)
	hit_points = hit_points_roll.roll()
	walking_speed = walking_speed_roll.roll()
	running_speed = running_speed_roll.roll()
	detection_distance = detection_distance_roll.roll()
	help_distance = help_distance_roll.roll()
	xp = hit_points
	set_collision_mask_value(Consts.LAYER_ROOFS, true)
	set_collision_layer_value(Consts.LAYER_ENEMY_CHARACTER, true)
	if (anim_tree != null):
		anim_state = anim_tree["parameters/playback"]
		var anim_die:AnimationNodeAnimation =  anim_tree.get_tree_root().get_node("die")
		anim_die_name = anim_die.animation
		anim_tree.connect("animation_finished", _on_animation_tree_animation_finished)
		anim_tree["parameters/attack/TimeScale/scale"] = GameMechanics.anim_scale(weapon.speed)
		anim_tree["parameters/idle_start/TimeSeek/seek_request"] = randf() * 10
		#timer_start_animation = Timer.new()
		#timer_start_animation.wait_time = randf()*5
		#timer_start_animation.connect("timeout", _on_start_timer_timeout)
		#add_child(timer_start_animation)
		#timer_start_animation.start()
	if (height == 0) and (collision_shape.shape is CylinderShape3D):
		height = collision_shape.shape.height
	raycast_detection = RayCast3D.new()
	raycast_detection.position.y += height
	raycast_detection.target_position = Vector3(0.0, 0.0, -detection_distance)
	raycast_detection.set_collision_mask_value(Consts.LAYER_ROOFS, true)
	raycast_detection.set_collision_mask_value(Consts.LAYER_ENEMY_CHARACTER, true)
	add_child(raycast_detection)
	label_info = Label.new()
	label_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_info.visible = false
	GameState.ui.hud.add_child(label_info)
	progress_hp = ProgressBar.new()
	progress_hp.max_value = hit_points
	progress_hp.value = hit_points
	progress_hp.show_percentage = false
	progress_hp.size.x = 50
	progress_hp.modulate = Color.RED
	GameState.ui.hud.add_child(progress_hp)
	timer_attack = Timer.new()
	timer_attack.process_callback = Timer.TIMER_PROCESS_PHYSICS
	timer_attack.one_shot = true
	timer_attack.wait_time = GameMechanics.attack_cooldown(weapon.speed)
	add_child(timer_attack)
	timer_attack.connect("timeout", _on_timer_attack_timeout)
	update_info()
	label_info.text = "%s" % label
	if (weapon.use_area != null):
		weapon.use_area.connect("body_entered", _on_item_hit)
	NotificationManager.connect("new_hit", _on_new_hit)
	NotificationManager.connect("node_call_for_help", _on_call_for_help)

func _on_start_timer_timeout():
	anim_tree.active = true
	anim_state.travel(ANIM_IDLE)
	timer_start_animation.queue_free()

func _process(delta):
	if (hit_points <= 0) or (not anim_tree.active): return
	if (GameState.player_state.hp <= 0):
		_idle()
		return
	var dist = position.distance_to(GameState.player.position)
	in_info_area = dist < info_distance
	update_label_info_position()
	var detected = (dist < hear_distance)
	if (not detected) and (dist < detection_distance):
		var forward_vector = -transform.basis.z
		var vector_to_player = (GameState.player.position - position).normalized()
		detected = acos(forward_vector.dot(vector_to_player)) <= deg_to_rad(75)
		move_to_detected_position = (raycast_detection.is_colliding() and not(raycast_detection.get_collider() is CharacterBody3D))
	if move_to_detected_position:
		_move_to_detected_position()
	elif (detected):
		_stop_idle()
		look_at(GameState.player.position)
		if (dist <= attack_distance):
			if (not attack_cooldown):
				anim_state.travel(ANIM_ATTACK)
				timer_attack.start()
				attack_cooldown = true
				hit_allowed = true
			return
		if (anim_state.get_current_node() != ANIM_RUN):
			print("%s detect run -%s-" % [name, anim_state.get_current_node()])
			anim_state.travel(ANIM_RUN)
			print(anim_state.get_travel_path ( ))
		detected_position = GameState.player.position
		velocity = -transform.basis.z * running_speed
		previous_position = position
		move_and_slide()
	else:
		_idle()

func _idle():
	var current = anim_state.get_current_node()
	if (current != ANIM_IDLE) and (current != ""):
		#print("idle from : %s" % anim_state.get_current_node())
		anim_state.travel(ANIM_IDLE)
	if ((idle_rotation_tween == null) or (not idle_rotation_tween.is_valid())) and (randf() < 0.1):
		var angle = randf_range(-45, 45)
		idle_rotation_tween = get_tree().create_tween()
		idle_rotation_tween.tween_property(
			self, # target
			"rotation_degrees:y", # target property
			rotation_degrees.y+angle, # end value
			10 # animation time
		)

func _stop_idle():
	if (idle_rotation_tween != null) and (idle_rotation_tween.is_valid()):
		idle_rotation_tween.kill()

func _move_to_detected_position():
	if (detected_position != Vector3.ZERO):
		_stop_idle()
		if (position.distance_to(previous_position) < 0.1):
			move_to_detected_position = false
			detected_position = Vector3.ZERO
		else:
			if (anim_state.get_current_node() != ANIM_RUN):
				#print("%s move to" % name)
				anim_state.travel(ANIM_RUN)
			look_at(detected_position)
			velocity = -transform.basis.z * running_speed
			previous_position = position
			move_and_slide()
	else:
		move_to_detected_position = false
		_idle()

func _to_string():
	return label

func update_info():
	if (label_info == null): return
	progress_hp.value = hit_points
	update_label_info_position()

func update_label_info_position():
	if (label_info == null): return
	label_info.visible = in_info_area and GameState.camera.size < 30
	progress_hp.visible = label_info.visible
	if (label_info.visible):
		var pos:Vector3 = position
		pos.y += height
		var pos2d:Vector2 = get_viewport().get_camera_3d().unproject_position(pos)
		progress_hp.position = pos2d
		progress_hp.position.x -= progress_hp.size.x / 2
		progress_hp.position.y -= progress_hp.size.y/2
		label_info.position = pos2d
		label_info.position.x -= label_info.size.x / 2
		label_info.position.y -= label_info.size.y + progress_hp.size.y
		label_info.add_theme_font_size_override("font_size", 14 - GameState.camera.size / 10)

func hit(hit_by:ItemWeapon):
	var damage_points = min(hit_by.damages_roll.roll(), hit_points)
	hit_points -= damage_points
	update_info()
	look_at(GameState.player.position)
	var pos = label_info.position
	pos.x += label_info.size.x / 2
	velocity = Vector3.ZERO
	NotificationManager.hit(self, hit_by, damage_points)
	if (anim_state != null):
		anim_state.travel(ANIM_HIT if hit_points > 0 else ANIM_DIE)
	if (hit_points < (progress_hp.max_value * 0.25)) and (not help_called) and (randf() < 0.25):
		help_called = true
		NotificationManager.call_for_help(self)
	if (hit_points <= 0):
		NotificationManager.xp(xp)
		label_info.queue_free()
		progress_hp.queue_free()
		raycast_detection.queue_free()
		weapon.queue_free()
		$CollisionShape3D.queue_free()
		NotificationManager.disconnect("new_hit", _on_new_hit)
		label_info = null
		in_info_area = false

func _on_new_hit(target:Node3D, weapon:ItemWeapon, damage_points:int, positive:bool):
	if positive and (target != self) and (position.distance_to(target.position) < detection_distance):
		if (randf() < 0.2):
			detected_position = target.position
			move_to_detected_position = true

func _on_call_for_help(sender:Node3D):
	if (sender is EnemyCharacter) and (sender != self) and (position.distance_to(sender.position) < (detection_distance * 2.0)):
		if (randf() < 0.2):
			detected_position = sender.position
			move_to_detected_position = true

func _on_timer_attack_timeout():
	attack_cooldown = false

func _on_item_hit(node:Node3D):
	if (hit_allowed):
		hit_allowed = false
		if (node is Player):
			node.hit(weapon)

func _on_input_event(camera, event, position, normal, shape_idx):
	if (event is InputEventMouseButton) and (event.button_index == MOUSE_BUTTON_MIDDLE) and not(event.pressed):
		Tools.load_dialog(self, Tools.DIALOG_ENEMY_INFO, GameState.resume_game).open(self)

func _on_animation_tree_animation_finished(anim_name):
	if (anim_name == "undead/react_death_backward_1"):
		anim_tree.queue_free()
		$AnimationPlayer.queue_free()
		process_mode = Node.PROCESS_MODE_DISABLED
