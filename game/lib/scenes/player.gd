class_name Player extends CharacterBody3D

signal start_moving()
signal stop_moving()

const ANIM_STANDING = "idle"
const ANIM_WALKING = "walk"
const ANIM_RUNNING = "run"
const ANIM_DIE = "die"
const ANIM_ATTACKING= "attack"
const ANIM_USING= "use"
const ANIM_SWORD_SLASH = "default/sword_slash_1_v1"

@export var camera_pivot:Node3D

@onready var interactions = $Interactions
@onready var anim_player:AnimationPlayer = $AnimationPlayer 
@onready var anim_tree:AnimationTree = $AnimationTree
@onready var timer_use:Timer = $TimerUse

const walking_speed:float = 7.0
const running_speed:float = 14.0
const walking_jump_impulse:float = 20.0

var anim_state:AnimationNodeStateMachinePlayback
var camera:IsometricCamera
var character:Node3D
var attach_item:Node3D

# for move_and_slide()
var speed:float = 0.0
var fall_acceleration:float = 200.0
var target_velocity:Vector3 = Vector3.ZERO
# for mouse clic-to-move
var move_to_target = null
var move_to_previous_position = null

# isometric current view rotation
var current_view:int = 0
# player movement signaled
var signaled:bool = false

# action animation playing
var attack_cooldown:bool = false
# one hit only allowed during attack cooldown
var hit_allowed:bool = false
# running animation playing
var running:bool = false
# approx height
var height = 1.7

const directions = {
	"forward" : 	[  { 'x':  1, 'z': -1 },  { 'x':  1, 'z':  1 },  { 'x': -1, 'z':  1 },  { 'x': -1, 'z': -1 } ],
	"left" : 		[  { 'x': -1, 'z': -1 },  { 'x':  1, 'z': -1 },  { 'x':  1, 'z':  1 },  { 'x': -1, 'z':  1 } ],
	"backward" : 	[  { 'x': -1, 'z':  1 },  { 'x': -1, 'z': -1 },  { 'x':  1, 'z': -1 },  { 'x':  1, 'z':  1 } ],
	"right" : 		[  { 'x':  1, 'z':  1 },  { 'x': -1, 'z':  1 },  { 'x': -1, 'z': -1 },  { 'x':  1, 'z': -1 } ]
}

func _ready():
	character = get_node("Character")
	anim_state = anim_tree["parameters/playback"]
	camera = camera_pivot.get_node("Camera")
	camera.connect("view_rotate", _on_view_rotate)
	attach_item = character.get_node("RootNode/Skeleton3D/HandAttachment/AttachmentPoint")

func _unhandled_input(_event):
	if (attack_cooldown) or (GameState.player_state.hp <= 0): return
	if Input.is_action_pressed("use") and (GameState.current_item != null) and (GameState.current_item is ItemWeapon) and (interactions.node_to_use == null):
		anim_state.travel(ANIM_ATTACKING)
		hit_allowed = true
		timer_use.wait_time = GameMechanics.attack_cooldown(GameState.current_item.speed)
		move_to_target = null
		running = false
		attack_cooldown = true
		timer_use.start()
	if Input.is_action_pressed("player_moveto"):
		move_to(get_viewport().get_mouse_position())
	elif Input.is_action_just_released("player_moveto"):
		stop_move_to()

func _physics_process(delta):
	if (GameState.player_state.hp <= 0) or attack_cooldown: return
	var on_floor = is_on_floor_only() 
	if (move_to_target != null):
		if Input.is_action_pressed("player_right") or  Input.is_action_pressed("player_left") or  Input.is_action_pressed("player_backward") or  Input.is_action_pressed("player_forward"):
			stop_move_to()
		else:
			var look_at_target = move_to_target
			look_at_target.y = position.y
			look_at(look_at_target)
			if (transform.origin.distance_to(move_to_target)) < 0.1:
				stop_move_to()
				return
			if Input.is_action_pressed("modifier"):
				if (not running):
					speed = running_speed
					anim_state.travel(ANIM_RUNNING)
					running = true
			else:
				running = false
				speed = walking_speed
				anim_state.travel(ANIM_WALKING)
			velocity = -transform.basis.z * speed
			if (move_to_target.y > position.y):
				for index in range(get_slide_collision_count()):
					var collision = get_slide_collision(index)
					var collider = collision.get_collider()
					if collider.is_in_group("stairs"):
						velocity.y = 5
			elif not on_floor:
				velocity.y = velocity.y - (fall_acceleration * 2 * delta)
			move_to_previous_position = position
			move_and_slide()
			if (position.distance_to(move_to_previous_position) < 0.001):
				stop_move_to()
				return
			_update_camera()
			return
		
	var no_jump = false
	var direction = Vector3.ZERO
	if Input.is_action_pressed("player_right"):
		direction.x += directions["right"][current_view].x
		direction.z += directions["right"][current_view].z
	if Input.is_action_pressed("player_left"):
		direction.x += directions["left"][current_view].x
		direction.z += directions["left"][current_view].z
	if Input.is_action_pressed("player_backward"):
		direction.x += directions["backward"][current_view].x
		direction.z += directions["backward"][current_view].z
	if Input.is_action_pressed("player_forward"):
		direction.x += directions["forward"][current_view].x
		direction.z += directions["forward"][current_view].z
	if direction != Vector3.ZERO:
		direction = direction.normalized()
		look_at(position + direction, Vector3.UP)
		if Input.is_action_pressed("modifier"):
			if (not running):
				speed = running_speed
				anim_state.travel(ANIM_RUNNING)
				running = true
		else:
			running = false
			speed = walking_speed
		anim_state.travel(ANIM_WALKING)
		for index in range(get_slide_collision_count()):
			var collision = get_slide_collision(index)
			var collider = collision.get_collider()
			if collider == null:
				continue
			if collider.is_in_group("stairs"):
				target_velocity.y = 5
				no_jump = true
			elif collider.is_in_group("ladders") and Input.is_action_pressed("player_jump"):
				target_velocity.y = 12
				no_jump = true
	else:
		target_velocity.y = 0
		signaled = false
		running = false
		stop_moving.emit()
		anim_state.travel("idle")
	
	target_velocity.x = direction.x * speed
	target_velocity.z = direction.z * speed
	
	if not on_floor:
		target_velocity.y = target_velocity.y - (fall_acceleration * delta)
	if on_floor and Input.is_action_just_pressed("player_jump") and !no_jump:
		target_velocity.y = walking_jump_impulse
		#anim.play(Consts.ANIM_JUMPING)
	velocity = target_velocity
	move_and_slide()
	if direction != Vector3.ZERO:
		_update_camera()

func move(pos:Vector3, rot:Vector3):
	position = pos
	rotation = rot
	_update_camera()

func _update_camera():
	camera_pivot.position = position
	camera_pivot.position.y += 1.5
	if (!signaled) :
		start_moving.emit()
		signaled = true

func move_to(target:Vector2):
	var ray_query = PhysicsRayQueryParameters3D.new()
	ray_query.collision_mask = 0x1
	ray_query.from = camera.project_ray_origin(target)
	ray_query.to = ray_query.from + camera.project_ray_normal(target) * 1000
	var iray = get_world_3d().direct_space_state.intersect_ray(ray_query)
	if (iray.size() > 0):
		move_to_target = iray.position

func stop_move_to():
	if (move_to_target != null):
		move_to_target = null
		velocity = Vector3.ZERO

func _look_at(node:Node3D):
	var pos = node.global_position
	pos.y = position.y
	look_at(pos)

func _on_view_rotate(view:int):
	current_view = view

#func print_property_list(parent):
#	print(parent.get_name())
#	var list = parent.get_property_list()
#	for prop in list:
#		print("	> " + prop["name"])
#	print("---")

func handle_item():
	attach_item.add_child(GameState.current_item)
	if (GameState.current_item is ItemWeapon):
		anim_tree["parameters/attack/TimeScale/scale"] = GameMechanics.anim_scale(GameState.current_item.speed)
	if (GameState.current_item.use_area != null):
		GameState.current_item.use_area.connect("body_entered", _on_item_hit)

func unhandle_item():
	if (GameState.current_item.use_area != null):
		GameState.current_item.use_area.disconnect("body_entered", _on_item_hit)
	attach_item.remove_child(GameState.current_item)

func hit(hit_by:ItemWeapon):
	if (GameState.player_state.hp <= 0): return
	var damage_points = min(hit_by.damages_roll.roll(), GameState.player_state.hp)
	GameState.player_state.hp -= damage_points
	var pos3d = global_position
	pos3d.y += height
	var pos = camera_pivot.camera.unproject_position(pos3d)
	velocity = Vector3.ZERO
	NotificationManager.hit(self, hit_by, damage_points, pos)
	if (GameState.player_state.hp  <= 0):
		anim_state.travel(ANIM_DIE)

func _on_item_hit(node:Node3D):
	if (hit_allowed):
		hit_allowed = false
		if (node is EnemyCharacter):
			look_at(node.global_position)
			node.hit(GameState.current_item)

func _on_timer_attack_timeout():
	attack_cooldown = false

func _to_string():
	return GameState.player_state.nickname

func _on_animation_tree_animation_finished(anim_name):
	if (anim_name == "default/die_backward_1"):
		Tools.load_dialog(self, Tools.DIALOG_GAMEOVER).open()
