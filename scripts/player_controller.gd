extends CharacterBody3D
class_name PlayerController

## 3D player — CharacterBody3D with Camera3D + RayCast3D.
## WASD: move, Space: jump, Shift: sprint, Mouse: look
## LMB: Fire (heat), RMB: Rain (water), Interact (E): fertilize

@export var move_speed: float = 5.0
@export var sprint_multiplier: float = 1.8
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002
@export var gravity: float = 12.0

var world: WorldGrid
var camera: Camera3D
var raycast: RayCast3D

func _ready() -> void:
	camera = get_node_or_null("Camera3D") as Camera3D
	if camera:
		raycast = camera.get_node_or_null("RayCast3D") as RayCast3D
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func initialize(start_world: WorldGrid) -> void:
	world = start_world
	if world:
		# Place player above ground
		global_position = Vector3(0, 2, 5)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		if camera:
			camera.rotate_x(-event.relative.y * mouse_sensitivity)
			camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-85), deg_to_rad(85))
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if event.is_action_pressed("interact"):
		_try_interact()

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Movement input
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_dir.y = Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed := move_speed
	if Input.is_action_pressed("sprint"):
		speed *= sprint_multiplier

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed * delta * 4.0)
		velocity.z = move_toward(velocity.z, 0, speed * delta * 4.0)

	move_and_slide()

	_handle_world_interaction()

func _handle_world_interaction() -> void:
	if world == null:
		return
	var grid_pos: Vector2i
	if raycast and raycast.is_colliding():
		var hit_pos: Vector3 = raycast.get_collision_point()
		grid_pos = world.world_to_grid(hit_pos)
	else:
		# Fallback: grid under player
		grid_pos = world.world_to_grid(global_position)

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		world.apply_heat(grid_pos.x, grid_pos.y, 50.0, 5)
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		world.apply_water(grid_pos.x, grid_pos.y, 0.1, 6)
		world.apply_heat(grid_pos.x, grid_pos.y, -10.0, 6)

func _try_interact() -> void:
	if world == null:
		return
	var grid_pos := world.world_to_grid(global_position)
	var idx := grid_pos.y * world.GRID_WIDTH + grid_pos.x
	if idx >= 0 and idx < world.nutrients.size():
		world.nutrients[idx] = minf(world.nutrients[idx] + 0.05, 1.0)
