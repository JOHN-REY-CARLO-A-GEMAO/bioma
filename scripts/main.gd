extends Node3D

## Main game manager — spawns the world, creatures, and player.

var world: WorldGrid
var player: PlayerController
var creatures: Array[Creature] = []
var creature_scene: PackedScene

@export var initial_creatures: int = 30
@export var max_creatures: int = 100
var spawn_timer: float = 0.0

# HUD
var hud: CanvasLayer
var info_label: Label

func _ready() -> void:
	# Create world
	world = WorldGrid.new()
	add_child(world)

	# Create player camera
	player = PlayerController.new()
	player.initialize(world)
	add_child(player)

	# Spawn initial creatures
	for i in range(initial_creatures):
		_spawn_creature()

	# Setup HUD
	_setup_hud()

func _process(delta: float) -> void:
	spawn_timer += delta

	# Creatures reproduce when well-fed
	if spawn_timer > 5.0 and creatures.size() < max_creatures:
		spawn_timer = 0.0
		for c in creatures:
			if c.is_alive and c.hunger > c.max_hunger * 0.8 and c.thirst > c.max_thirst * 0.7:
				if randf() < 0.1:  # 10% chance per eligible creature
					_spawn_creature_near(c.position)
					break

	# Clean up dead creatures after a while
	creatures = creatures.filter(func(c): return c.is_alive or c.age < 10.0)

	# Update HUD
	var alive_count := creatures.filter(func(c): return c.is_alive).size()
	info_label.text = (
		"BIOMA: The First Law\n" +
		"─────────────────\n" +
		"Creatures: %d / %d\n" % [alive_count, max_creatures] +
		"Tick: %d\n" % world.tick_count +
		"─────────────────\n" +
		"LMB: 🔥 Fire  |  RMB: 💧 Rain\n" +
		"MMB: 🌱 Fertilize  |  WASD: Move\n" +
        "PgUp/PgDn: Zoom"
	)

func _spawn_creature() -> void:
	var c := Creature.new()
	var spawn_pos := Vector3(
		randf_range(-14, 14),
		0.5,
		randf_range(-14, 14)
	)
	add_child(c)
	c.initialize(world, spawn_pos)
	creatures.append(c)

func _spawn_creature_near(pos: Vector3) -> void:
	var c := Creature.new()
	var offset := Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	add_child(c)
	c.initialize(world, pos + offset)
	creatures.append(c)

func _setup_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	info_label = Label.new()
	info_label.position = Vector2(10, 10)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.add_theme_font_size_override("font_size", 14)
	hud.add_child(info_label)
