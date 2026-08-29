extends CharacterBody3D
class_name Creature

## Fully autonomous 3D agent driven by physiological needs.
## No scripted behavior — everything emerges from survival drives.

@export var max_health: float = 100.0
@export var max_hunger: float = 100.0
@export var max_thirst: float = 100.0
@export var metabolism_rate: float = 0.5
@export var move_speed: float = 2.5
@export var sense_radius: int = 15  # Grid cells
@export var gravity: float = 10.0

var health: float
var hunger: float
var thirst: float
var body_temp: float = 310.0  # ~37°C (mammalian)
var age: float = 0.0
var is_alive: bool = true

var world: WorldGrid
var target_cell: Vector2i = Vector2i(-1, -1)
var wander_timer: float = 0.0
var nav_agent: NavigationAgent3D

# Visual
var mesh_instance: MeshInstance3D

enum State { IDLE, SEEKING_FOOD, SEEKING_WATER, FLEEING_HEAT, WANDERING, DEAD }
var current_state: State = State.WANDERING

func _ready() -> void:
	health = max_health
	hunger = max_hunger * 0.7
	thirst = max_thirst * 0.7
	nav_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	add_to_group("creatures")

func initialize(start_world: WorldGrid, start_pos: Vector3) -> void:
	world = start_world
	global_position = start_pos

func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	age += delta
	_update_physiology(delta)
	_decide_behavior(delta)
	_move(delta)
	_update_visuals()

func _update_physiology(delta: float) -> void:
	if world == null:
		return
	var grid_pos := world.world_to_grid(global_position)
	var cell := world.get_cell_data(grid_pos.x, grid_pos.y)
	if cell.is_empty():
		return

	# Metabolism burns calories
	hunger -= metabolism_rate * delta
	thirst -= metabolism_rate * 1.2 * delta  # Thirst faster than hunger

	# Body temp regulation
	var env_temp: float = cell["temperature"]
	body_temp += (env_temp - body_temp) * 0.01 * delta

	# Drink if standing in water
	if cell["moisture"] > 0.4:
		thirst = minf(thirst + 20.0 * delta, max_thirst)

	# Eat if standing in vegetation
	if cell["biomass"] > 0.2:
		var eaten := world.consume_biomass(grid_pos.x, grid_pos.y, 0.5 * delta)
		hunger = minf(hunger + eaten * 30.0, max_hunger)

	# Damage from extremes
	if hunger <= 0:
		health -= 5.0 * delta
		hunger = 0
	if thirst <= 0:
		health -= 8.0 * delta  # Dehydration kills faster
		thirst = 0
	if body_temp > 320.0:
		health -= (body_temp - 320.0) * 0.5 * delta  # Heatstroke
	if body_temp < 295.0:
		health -= (295.0 - body_temp) * 0.3 * delta  # Hypothermia

	if health <= 0:
		_die()

func _decide_behavior(delta: float) -> void:
	## Priority-based drive system — most urgent need wins
	if world == null:
		return
	var grid_pos := world.world_to_grid(global_position)

	if thirst < max_thirst * 0.3:
		current_state = State.SEEKING_WATER
		target_cell = _find_best_cell(grid_pos, "moisture", true)
	elif hunger < max_hunger * 0.3:
		current_state = State.SEEKING_FOOD
		target_cell = _find_best_cell(grid_pos, "biomass", true)
	elif body_temp > 315.0:
		current_state = State.FLEEING_HEAT
		target_cell = _find_best_cell(grid_pos, "temperature", false)  # Seek cool
	else:
		current_state = State.WANDERING
		wander_timer -= delta
		if wander_timer <= 0:
			target_cell = grid_pos + Vector2i(
				randi_range(-10, 10),
				randi_range(-10, 10)
			)
			wander_timer = randf_range(2.0, 5.0)

func _find_best_cell(center: Vector2i, property: String, seek_high: bool) -> Vector2i:
	## Scan nearby cells for the best value of a property
	var best_pos := center
	var best_val := -999.0 if seek_high else 9999.0

	# Sample in a spiral pattern for performance
	for dy in range(-sense_radius, sense_radius + 1, 3):
		for dx in range(-sense_radius, sense_radius + 1, 3):
			var check := center + Vector2i(dx, dy)
			var cell := world.get_cell_data(check.x, check.y)
			if cell.is_empty():
				continue

			var val: float = cell[property]
			if seek_high and val > best_val:
				best_val = val
				best_pos = check
			elif not seek_high and val < best_val:
				best_val = val
				best_pos = check

	return best_pos

func _move(delta: float) -> void:
	if target_cell == Vector2i(-1, -1):
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	var target_world := world.grid_to_world_3d(target_cell)
	var direction := (target_world - global_position)
	direction.y = 0
	var distance := Vector2(global_position.x, global_position.z).distance_to(Vector2(target_world.x, target_world.z))

	if distance > 0.5:
		direction = direction.normalized()
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		if nav_agent:
			nav_agent.target_position = target_world
			# optionally use nav_agent.get_next_path_position() for avoidance
		move_and_slide()
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

func _die() -> void:
	is_alive = false
	current_state = State.DEAD
	if mesh_instance and mesh_instance.mesh:
		# Tint red/gray to indicate death
		pass

	# Return nutrients to the soil
	if world:
		var grid_pos := world.world_to_grid(global_position)
		var idx := grid_pos.y * world.GRID_WIDTH + grid_pos.x
		if idx >= 0 and idx < world.nutrients.size():
			world.nutrients[idx] += 0.3  # Decomposing body fertilizes soil
	# Optional: disable collision/shape after death
	set_physics_process(false)

func _update_visuals() -> void:
	if mesh_instance == null:
		return
	# Color reflects state (use StandardMaterial3D albedo)
	var mat: StandardMaterial3D = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mesh_instance.set_surface_override_material(0, mat)
	match current_state:
		State.SEEKING_FOOD:
			mat.albedo_color = Color(0.8, 0.6, 0.2)
		State.SEEKING_WATER:
			mat.albedo_color = Color(0.2, 0.4, 0.8)
		State.FLEEING_HEAT:
			mat.albedo_color = Color(0.9, 0.2, 0.2)
		State.DEAD:
			mat.albedo_color = Color(0.3, 0.2, 0.2, 0.5)
		_:
			var health_ratio := health / max_health
			mat.albedo_color = Color(
				0.3 + (1.0 - health_ratio) * 0.5,
				0.5 + health_ratio * 0.4,
				0.2
			)
