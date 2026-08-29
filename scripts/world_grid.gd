extends Node3D
class_name WorldGrid

## Every cell in the world has real thermodynamic properties.
## No arbitrary game logic — everything emerges from physics.

# 3D grid properties expected by main.tscn (Node3D)
@export var grid_size: Vector3i = Vector3i(32, 16, 32)
@export var cell_size: float = 1.0

# Determinism (sprint checkpoint #1): any non-negative seed reproduces the
# same world on the same engine version; -1 = fresh random world each run.
@export var world_seed: int = -1

# Legacy 2D constants kept for compatibility with existing simulation code
const CELL_SIZE := 8
const GRID_WIDTH := 160   # 1280px / 8
const GRID_HEIGHT := 90   # 720px / 8

# --- Cell Data Arrays (SoA for cache performance) ---
var temperature: PackedFloat32Array    # Kelvin (273-373 typical)
var moisture: PackedFloat32Array       # 0.0 (bone dry) to 1.0 (flooded)
var biomass: PackedFloat32Array        # 0.0 (barren) to 1.0 (dense forest)
var nutrients: PackedFloat32Array      # 0.0 to 1.0 (soil fertility)
var elevation: PackedFloat32Array      # 0.0 to 1.0 (affects water flow)

# --- Simulation Parameters ---
@export var ambient_temp: float = 293.0       # ~20°C
@export var solar_intensity: float = 0.3      # Sun heating factor
@export var heat_diffusion_rate: float = 0.02
@export var evaporation_rate: float = 0.005
@export var rainfall_rate: float = 0.001
@export var vegetation_growth_rate: float = 0.002
@export var combustion_threshold_temp: float = 373.0  # 100°C
@export var combustion_min_biomass: float = 0.3
@export var decomposition_rate: float = 0.001

var tick_count: int = 0
var is_simulating: bool = true

# Rendering
var image: Image
var texture: ImageTexture
var sprite: Sprite2D

func _ready() -> void:
	_initialize_grid(world_seed)
	_setup_rendering()

func _initialize_grid(init_seed: int = -1) -> void:
	# Recreate every buffer so first initialization and resets begin from the
	# same empty state. Packed arrays do not grow through indexed assignment.
	var cell_count := GRID_WIDTH * GRID_HEIGHT
	temperature = PackedFloat32Array()
	temperature.resize(cell_count)
	moisture = PackedFloat32Array()
	moisture.resize(cell_count)
	biomass = PackedFloat32Array()
	biomass.resize(cell_count)
	nutrients = PackedFloat32Array()
	nutrients.resize(cell_count)
	elevation = PackedFloat32Array()
	elevation.resize(cell_count)

	# All randomness flows through one seeded RNG so a single seed reproduces
	# the entire world (noise seeds, temperature jitter, biomass scatter,
	# nutrient spread). Legacy code used the auto-seeded global RNG, which
	# could not be reproduced; seeded worlds therefore have no legacy
	# counterpart — by design.
	var rng := RandomNumberGenerator.new()
	if init_seed >= 0:
		rng.seed = init_seed
	else:
		rng.randomize()

	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02

	var moisture_noise := FastNoiseLite.new()
	moisture_noise.seed = rng.randi()
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.frequency = 0.015

	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var idx := _idx(x, y)

			# Generate terrain
			var e := (noise.get_noise_2d(x, y) + 1.0) * 0.5
			elevation[idx] = e

			# Temperature varies with elevation (lapse rate)
			temperature[idx] = ambient_temp - (e * 15.0) + rng.randf_range(-2, 2)

			# Moisture: lowlands are wetter, highlands drier
			var m := (moisture_noise.get_noise_2d(x, y) + 1.0) * 0.5
			moisture[idx] = clampf(m + (1.0 - e) * 0.3, 0.0, 1.0)

			# Biomass grows where conditions are good
			var growth_potential := _calc_growth_potential(
				temperature[idx], moisture[idx], nutrients[idx]
			)
			biomass[idx] = clampf(growth_potential * rng.randf(), 0.0, 0.8)

			# Nutrients start moderate
			nutrients[idx] = rng.randf_range(0.2, 0.6)

func _setup_rendering() -> void:
	image = Image.create(GRID_WIDTH, GRID_HEIGHT, false, Image.FORMAT_RGB8)
	texture = ImageTexture.create_from_image(image)
	sprite = Sprite2D.new()
	sprite.texture = texture
	sprite.scale = Vector2(CELL_SIZE, CELL_SIZE)
	sprite.position = Vector2.ZERO
	add_child(sprite)

func _process(_delta: float) -> void:
	if not is_simulating:
		return

	# Run simulation at ~10 ticks/sec for stability
	tick_count += 1
	if tick_count % 6 == 0:
		_simulate_thermodynamics()
		_simulate_ecosystem()
		_render_grid()

func _simulate_thermodynamics() -> void:
	## WorldGrid is the scene adapter; SimCore owns the state transform.
	var next_state := SimCore.simulate_thermodynamics(
		temperature,
		moisture,
		elevation,
		GRID_WIDTH,
		GRID_HEIGHT,
		ambient_temp,
		solar_intensity,
		heat_diffusion_rate,
		evaporation_rate,
		rainfall_rate,
	)
	temperature = next_state["temperature"]
	moisture = next_state["moisture"]

func _simulate_ecosystem() -> void:
	## WorldGrid is the scene adapter; SimCore owns the state transform.
	var next_state := SimCore.simulate_ecosystem(
		temperature,
		moisture,
		biomass,
		nutrients,
		GRID_WIDTH,
		GRID_HEIGHT,
		vegetation_growth_rate,
		combustion_threshold_temp,
		combustion_min_biomass,
		decomposition_rate,
	)
	temperature = next_state["temperature"]
	moisture = next_state["moisture"]
	biomass = next_state["biomass"]
	nutrients = next_state["nutrients"]

func _calc_growth_potential(temp: float, moist: float, nutr: float) -> float:
	## Delegates to the extracted, headless-testable core (SimCore).
	## Values identical to gm-baseline — guarded by tests/unit/test_sim_core.gd.
	return SimCore.calc_growth_potential(temp, moist, nutr)

func _render_grid() -> void:
	## Maps simulation data to pixel colors
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var idx := _idx(x, y)
			var color := Color.BLACK

			var t := temperature[idx]
			var m := moisture[idx]
			var b := biomass[idx]
			var n := nutrients[idx]

			if b > 0.1:
				# Vegetation: green, darker = denser
				var g := 0.2 + b * 0.6
				var r := 0.1 + n * 0.15  # Nutrient-rich = slightly yellow
				var bl := 0.05
				color = Color(r, g, bl)

				# Fire overlay
				if t > combustion_threshold_temp and m < 0.2:
					color = Color(1.0, 0.3 + randf() * 0.4, 0.0)
			elif m > 0.5:
				# Water: blue
				color = Color(0.1, 0.2, 0.5 + m * 0.3)
			elif t > 340.0:
				# Hot barren: red/orange
				color = Color(0.6, 0.2, 0.05)
			else:
				# Barren ground: brown/gray based on elevation
				var base := 0.2 + elevation[idx] * 0.3
				color = Color(base, base * 0.8, base * 0.5)

			image.set_pixel(x, y, color)

	texture.update(image)

# --- Public API for Player & Creatures ---

func get_cell_data(x: int, y: int) -> Dictionary:
	if x < 0 or x >= GRID_WIDTH or y < 0 or y >= GRID_HEIGHT:
		return {}
	var idx := _idx(x, y)
	return {
		"temperature": temperature[idx],
		"moisture": moisture[idx],
		"biomass": biomass[idx],
		"nutrients": nutrients[idx],
		"elevation": elevation[idx]
	}

func apply_heat(x: int, y: int, amount: float, radius: int = 3) -> void:
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and nx < GRID_WIDTH and ny >= 0 and ny < GRID_HEIGHT:
				var dist := Vector2(dx, dy).length()
				if dist <= radius:
					var falloff := 1.0 - (dist / radius)
					temperature[_idx(nx, ny)] += amount * falloff

func apply_water(x: int, y: int, amount: float, radius: int = 3) -> void:
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and nx < GRID_WIDTH and ny >= 0 and ny < GRID_HEIGHT:
				var dist := Vector2(dx, dy).length()
				if dist <= radius:
					var falloff := 1.0 - (dist / radius)
					moisture[_idx(nx, ny)] += amount * falloff

func consume_biomass(x: int, y: int, amount: float) -> float:
	if x < 0 or x >= GRID_WIDTH or y < 0 or y >= GRID_HEIGHT:
		return 0.0
	var idx := _idx(x, y)
	var consumed := minf(biomass[idx], amount)
	biomass[idx] -= consumed
	return consumed

func world_to_grid(world_pos: Variant) -> Vector2i:
	# Supports both Vector2 (legacy 2D) and Vector3 (3D world) inputs
	if world_pos is Vector3:
		return Vector2i(
			int(world_pos.x / cell_size) if cell_size != 0 else int(world_pos.x / CELL_SIZE),
			int(world_pos.z / cell_size) if cell_size != 0 else int(world_pos.z / CELL_SIZE)
		)
	elif world_pos is Vector2:
		return Vector2i(
			int(world_pos.x / CELL_SIZE),
			int(world_pos.y / CELL_SIZE)
		)
	elif world_pos is Vector2i:
		return world_pos
	elif world_pos is Vector3i:
		return Vector2i(world_pos.x, world_pos.z)
	else:
		push_warning("world_to_grid: expected Vector2/Vector3, got %s" % typeof(world_pos))
		return Vector2i.ZERO

func grid_to_world(grid_pos: Variant) -> Vector2:
	var x: int
	var y: int
	if grid_pos is Vector2i:
		x = grid_pos.x
		y = grid_pos.y
	elif grid_pos is Vector3i:
		x = grid_pos.x
		y = grid_pos.z
	else:
		push_warning("grid_to_world: expected Vector2i, got %s" % typeof(grid_pos))
		return Vector2.ZERO
	return Vector2(
		x * CELL_SIZE + CELL_SIZE / 2.0,
		y * CELL_SIZE + CELL_SIZE / 2.0
	)

func grid_to_world_3d(grid_pos: Variant) -> Vector3:
	# 3D helper for CharacterBody3D logic
	if grid_pos is Vector2i:
		return Vector3(grid_pos.x * cell_size + cell_size * 0.5, 0.5, grid_pos.y * cell_size + cell_size * 0.5)
	elif grid_pos is Vector3i:
		return Vector3(grid_pos.x * cell_size + cell_size * 0.5, float(grid_pos.y) * cell_size, grid_pos.z * cell_size + cell_size * 0.5)
	elif grid_pos is Vector2:
		return Vector3(grid_pos.x, 0.5, grid_pos.y)
	else:
		return Vector3.ZERO

func get_neighbors(pos: Variant, include_diagonal: bool = false) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var p: Vector3i
	if pos is Vector2i:
		p = Vector3i(pos.x, pos.y, 0)
	elif pos is Vector3i:
		p = pos
	else:
		return result
	# Von Neumann neighborhood (6 orthogonal) by default
	var offsets: Array[Vector3i] = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	if include_diagonal:
		# Moore neighborhood: all 26 surrounding cells in 3D
		offsets.clear()
		for dz in range(-1, 2):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0 and dz == 0:
						continue
					offsets.append(Vector3i(dx, dy, dz))
	for off in offsets:
		result.append(p + off)
	return result

func _idx(x: int, y: int) -> int:
	return y * GRID_WIDTH + x
