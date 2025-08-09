extends CharacterBody3D

#movement variables
var speed = 7
@export var run_speed: float = 7.0

#acceleration
@export var ACCEL_DEFAULT: float = 10.0
@export var ACCEL_AIR: float = 5.0
@onready var accel = ACCEL_DEFAULT

#jump
@export var gravity: float = 30.0
@export var jump: float = 15.0

#physics
var player_velocity
@export var inertia: int = 200
var movement_enabled = true
var gravity_enabled = true
var is_falling

#camera
var cam_accel = 40
@export var mouse_sense: float = 0.1
var snap
var angular_velocity = 15

#Vectors
var direction = Vector3()
var velocity = Vector3()
var gravity_direction = Vector3()
var movement = Vector3()

#references
@onready var mesh = $Player
@onready var collider = $CollisionShape3D
@onready var head = $Head
@onready var head_pos = head.transform
@onready var campivot = $Head/Camera_holder
@onready var camera = $Head/Camera_holder/Camera3D

func _ready():
	#mesh no longer inherits rotation of parent, allowing it to rotate freely
	mesh.set_as_top_level(true)
	set_process_input(true)
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	#get mouse input for camera rotation
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sense))
		head.rotate_x(deg_to_rad(-event.relative.y * mouse_sense))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _process(delta):
	#turns body in the direction of movement
	if direction != Vector3.ZERO:
		mesh.rotation.y = lerp_angle(mesh.rotation.y, atan2(-direction.x, -direction.z), angular_velocity * delta)

	physics_interpolation(delta)

func _physics_process(delta):
	input()
	_movement(delta)

func input():
	#get keyboard input
	direction = Vector3.ZERO
	var h_rot = global_transform.basis.get_euler().y
	var f_input = Input.get_action_strength("back") - Input.get_action_strength("forward")
	var h_input = Input.get_action_strength("right") - Input.get_action_strength("left")
	direction = Vector3(h_input, 0, f_input).rotated(Vector3.UP, h_rot).normalized()

func _jump():
	snap = Vector3.ZERO
	gravity_direction = Vector3.UP * jump

func _movement(delta):
	
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
		gravity_direction += Vector3.DOWN * gravity * delta
		
	#jump
	if Input.is_action_just_pressed("jump") :
		_jump()
	
	#make it move#
	if movement_enabled:
		velocity = velocity.lerp(direction * speed, accel * delta)
	
	if gravity_enabled:
		movement = velocity + gravity_direction
	else:
		movement = velocity
	
	set_velocity(movement)
	# TODOConverter3To4 looks that snap in Godot 4 is float, not vector like in Godot 3 - previous value `snap`
	set_up_direction(Vector3.UP)
	set_floor_stop_on_slope_enabled(false)
	set_max_slides(4)
	set_floor_max_angle(PI/4)
	# TODOConverter3To4 infinite_inertia were removed in Godot 4 - previous value `false`
	move_and_slide()
	
	#Rigidbody collisions
	for index in get_slide_collision_count():
		var collision = get_slide_collision(index)
		if collision.collider.is_in_group("Bodies"):
			collision.collider.apply_central_impulse(-collision.normal * inertia)

func physics_interpolation(delta):
	#physics interpolation to reduce jitter on high refresh-rate monitors
	var fps = Engine.get_frames_per_second()
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
