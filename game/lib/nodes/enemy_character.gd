class_name EnemyCharacter extends CharacterBody3D

const ANIM_IDLE = "idle"
const ANIM_WALK = "walk"
const ANIM_RUN = "run"
const ANIM_ATTACK = "attack"
const ANIM_DIE = "die"
const ANIM_HIT = "hit"

@export var label:String = "Enemy"
@export var damages:DicesRoll 
@export var attack_speed:int = 1
@export var hit_points_start:DicesRoll
@export var walking_speed:float = 0.5
@export var running_speed:float = 1.0
@export var info_distance:float = 10
@export var detection_distance:float = 6
@export var hear_distance:float = 2
@export var attack_distance:float = 0.9

@onready var anim_tree:AnimationTree = $AnimationTree
@onready var collision_shape:CollisionShape3D = $CollisionShape3D

var anim_state:AnimationNodeStateMachinePlayback
var label_info:Label
var collision_height:float = 0.0
var hit_points:int
var xp:int
var anim_die_name:String
var in_info_area:bool = false
var timer_attack:Timer
var attack_cooldown:bool = false

func _ready():
	hit_points = hit_points_start.roll()
	xp = hit_points
	set_collision_layer_value(Consts.LAYER_ENEMY_CHARACTER, true)
	if (anim_tree != null):
		anim_state = anim_tree["parameters/playback"]
		var anim_die:AnimationNodeAnimation =  anim_tree.get_tree_root().get_node("die")
		anim_die_name = anim_die.animation
	if (collision_shape.shape is CylinderShape3D):
		collision_height = collision_shape.shape.height
	label_info = Label.new()
	label_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_info.visible = false
	add_child(label_info)
	timer_attack = Timer.new()
	timer_attack.process_callback = Timer.TIMER_PROCESS_PHYSICS
	timer_attack.one_shot = true
	timer_attack.wait_time = Consts.ATTACK_COOLDOWN[attack_speed-1]
	add_child(timer_attack)
	timer_attack.connect("timeout", _on_timer_attack_timeout)
	update_info()

func _process(delta):
	if (hit_points <= 0): return
	var dist = position.distance_to(GameState.player.position)
	in_info_area = dist < info_distance
	update_label_info_position()
	if (dist < detection_distance):
		var detected = (dist < hear_distance)
		if (not detected):
			var forward_vector = -get_transform().basis.z
			var vector_to_player = (GameState.player.position - position).normalized()
			detected = acos(forward_vector.dot(vector_to_player)) <= deg_to_rad(60)
		if (detected):
			velocity = Vector3.ZERO
			# raycast
			look_at(GameState.player.position)
			if (dist > attack_distance):
				velocity = -transform.basis.z * running_speed
				anim_state.travel(ANIM_RUN)
				move_and_slide()
			elif not attack_cooldown:
				anim_state.travel(ANIM_ATTACK)
				timer_attack.start()
				attack_cooldown = true
			return
	anim_state.travel(ANIM_IDLE)
	if (randf() < 0.1):
		rotate_y(deg_to_rad(randf_range(-10, 10)))

func _to_string():
	return label

func update_info():
	if (label_info == null): return
	label_info.text = "%s\nHP:%d DMG:%s" % [ label, hit_points, damages ]
	update_label_info_position()

func update_label_info_position():
	if (label_info == null): return
	label_info.visible = in_info_area and GameState.camera.size < 30
	if (label_info.visible):
		var pos = position
		pos.y += collision_height
		label_info.position = get_viewport().get_camera_3d().unproject_position(pos)
		label_info.position.x -= label_info.size.x / 2
		label_info.position.y -= label_info.size.y
		label_info.add_theme_font_size_override("font_size", 14 - GameState.camera.size / 10)

func hit(hit_by:ItemWeapon):
	var damage_points = min(hit_by.damage.roll(), hit_points)
	hit_points -= damage_points
	update_info()
	look_at(GameState.player.position)
	var pos = label_info.position
	pos.x += label_info.size.x / 2
	velocity = Vector3.ZERO
	NotificationManager.hit(self, hit_by, damage_points, pos)
	if (anim_state != null):
		anim_state.travel(ANIM_HIT if hit_points > 0 else ANIM_DIE)
	if (hit_points <= 0):
		NotificationManager.xp(xp)
		set_collision_layer_value(Consts.LAYER_ENEMY_CHARACTER, false)
		set_collision_layer_value(Consts.LAYER_WORLD, true)
		label_info.queue_free()
		label_info = null
		in_info_area = false

func _on_timer_attack_timeout():
	attack_cooldown = false
