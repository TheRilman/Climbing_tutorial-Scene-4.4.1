extends CharacterBody3D

#movement variables
var speed: float = 7.0
@export var run_speed: float = 7.0
@export var climb_speed: float = 3.0
@export var stick_speed: float = 5.0

#acceleration
@export var ACCEL_DEFAULT: float = 10.0
@export var ACCEL_AIR: float = 5.0
@onready var accel: float = ACCEL_DEFAULT

#jump
@export var gravity: float = 30.0
@export var jump: float = 15.0

#physics
var player_velocity: Vector3
@export var inertia: int = 200
var movement_enabled: bool = true
var gravity_enabled: bool = true
var is_falling: bool

#camera
var cam_accel: float = 40.0
@export var mouse_sense: float = 0.1
var snap: Vector3
var angular_velocity: float = 15.0

#Vectors
var direction: Vector3 = Vector3()
var gravity_direction: Vector3 = Vector3()
var movement: Vector3 = Vector3()
var movement_velocity: Vector3 = Vector3()

#references
@onready var mesh: Node3D = $Player
@onready var collider: CollisionShape3D = $CollisionShape3D
@onready var head: Node3D = $Head
@onready var head_pos: Transform3D = head.transform
@onready var campivot: Node3D = $Head/Camera_holder
@onready var camera: Camera3D = $Head/Camera_holder/Camera3D

#climbing
@onready var still_on_wall_check: RayCast3D = $Player/Wall_check/still_on_wall_check
@onready var wall_check: RayCast3D = $Player/Wall_check/wall_check
@onready var stick_point_holder: Node3D = $Player/Wall_check/Stick_point_holder
@onready var stick_point: Marker3D = $Player/Wall_check/Stick_point_holder/Stick_point
var is_climbing: bool = false

func _ready() -> void:
	#mesh no longer inherits rotation of parent, allowing it to rotate freely
	mesh.set_as_top_level(true)
	set_process_input(true)
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	floor_stop_on_slope = false
	max_slides = 4
	floor_max_angle = PI / 4
	
	wall_check.collision_mask = 3
	still_on_wall_check.collision_mask = 3
	
	wall_check.collision_mask = 4  # Only Layer 3 ("Climbable")
	still_on_wall_check.collision_mask = 4  # Only Layer 3 ("Climbable")

func _input(event: InputEvent) -> void:
	#get mouse input for camera rotation
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sense))
		head.rotate_x(deg_to_rad(-event.relative.y * mouse_sense))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _process(delta: float) -> void:
	#turns body in the direction of movement
	if is_climbing:
		var normal: Vector3 = wall_check.get_collision_normal()
		var rot: float = atan2(normal.x, normal.z)
		mesh.rotation.y = lerp_angle(mesh.rotation.y, rot, angular_velocity * delta)
	elif direction != Vector3.ZERO:
		mesh.rotation.y = lerp_angle(mesh.rotation.y, atan2(-direction.x, -direction.z), angular_velocity * delta)
	
	physics_interpolation(delta)

func _physics_process(delta: float) -> void:
	input()
	climbing()
	_movement(delta)

func input() -> void:
	#get keyboard input
	if !is_climbing:
		direction = Vector3.ZERO
		var h_rot: float = global_transform.basis.get_euler().y
		var f_input: float = Input.get_action_strength("back") - Input.get_action_strength("forward")
		var h_input: float = Input.get_action_strength("right") - Input.get_action_strength("left")
		direction = Vector3(h_input, 0, f_input).rotated(Vector3.UP, h_rot).normalized()

func _jump() -> void:
	snap = Vector3.ZERO
	gravity_direction = Vector3.UP * jump

func climbing() -> void:
	#check if player is able to climb
	if wall_check.is_colliding():
		if still_on_wall_check.is_colliding():
			if Input.is_key_pressed(KEY_F):
				is_climbing = true
			else:
				is_climbing = false
		else:
			#if player is at the top of a climb, boost them over the top
			_jump()
			await get_tree().create_timer(0.3).timeout
			is_climbing = false
	else:
		is_climbing = false
	
	
	if is_climbing:
		#if player is climbing disable gravity
		gravity_enabled = false
		speed = climb_speed
		gravity_direction = Vector3.ZERO #gravity is set to zero to prevent it building up
		
		# calculate direction
		var normal: Vector3 = wall_check.get_collision_normal()
		var rot: float = atan2(normal.x, normal.z)
		var f_input: float = Input.get_action_strength("forward") - Input.get_action_strength("back")
		var h_input: float = Input.get_action_strength("right") - Input.get_action_strength("left")
		direction = Vector3(h_input, f_input, 0).rotated(Vector3.UP, rot).normalized() 
	else:
		speed = run_speed
		gravity_enabled = true

func _movement(delta: float) -> void:
	
	#jumping and gravity
	if is_on_floor():
		snap = -get_floor_normal()
		accel = ACCEL_DEFAULT
		gravity_direction = Vector3.ZERO
	elif is_on_ceiling():
		gravity_direction = Vector3.ZERO
	else:
		snap = Vector3.DOWN
		accel = ACCEL_AIR
		if gravity_enabled:
			gravity_direction += Vector3.DOWN * gravity * delta
		
	#jump
	if Input.is_action_just_pressed("jump") :
		_jump()
	
	#make it move#
	if movement_enabled:
		movement_velocity = movement_velocity.lerp(direction * speed, accel * delta)
	
	self.velocity = movement_velocity + gravity_direction
	
	if is_climbing:
		var normal: Vector3 = wall_check.get_collision_normal()
		self.velocity += -normal * stick_speed
	
	up_direction = Vector3.UP
	
	if is_climbing:
		motion_mode = MOTION_MODE_FLOATING
		floor_snap_length = 0.0
	else:
		motion_mode = MOTION_MODE_GROUNDED
		if snap == Vector3.ZERO:
			floor_snap_length = 0.0
		else:
			floor_snap_length = 0.2
	
	move_and_slide()
	
	#Rigidbody collisions
	for index: int in get_slide_collision_count():
		var collision: KinematicCollision3D = get_slide_collision(index)
		if collision.get_collider().is_in_group("Bodies"):
			collision.get_collider().apply_central_impulse(-collision.get_normal() * inertia)

func physics_interpolation(delta: float) -> void:
	#physics interpolation to reduce jitter on high refresh-rate monitors
	var fps: float = Engine.get_frames_per_second()
	if fps > Engine.physics_ticks_per_second:
		campivot.set_as_top_level(true)
		campivot.global_transform.origin = campivot.global_transform.origin.lerp(head.global_transform.origin, cam_accel * delta)
		campivot.rotation.y = rotation.y
		campivot.rotation.x = head.rotation.x
		mesh.global_transform.origin = mesh.global_transform.origin.lerp(global_transform.origin, cam_accel * delta)
	else:
		campivot.set_as_top_level(false)
		campivot.global_transform = head.global_transform
		mesh.global_transform.origin = global_transform.origin
