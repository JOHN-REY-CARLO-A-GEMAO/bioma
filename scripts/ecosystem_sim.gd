class_name EcosystemSim
extends Node
## High-level ecosystem tick: couples WorldGrid + ChemistryEngine + creatures.
## Handles energy flow, reproduction, nutrient cycling, and population stats.

@export var tick_interval: float = 0.5
@export var auto_tick: bool = true

var world_grid: WorldGrid
var chemistry: ChemistryEngine

var _tick_timer: float = 0.0
var _population: Dictionary = {}  # String species -> int

signal tick_completed(tick_count: int, stats: Dictionary)
signal species_extinct(species: String)
signal population_changed(species: String, count: int)

var _tick_count: int = 0

func _ready() -> void:
	world_grid = get_parent().find_child("WorldGrid", true, false) as WorldGrid
	chemistry = get_parent().find_child("ChemistryEngine", true, false) as ChemistryEngine
	if world_grid == null:
		push_warning("[EcosystemSim] WorldGrid not found as sibling/child.")
	if chemistry == null:
		push_warning("[EcosystemSim] ChemistryEngine not found as sibling/child.")

func _process(delta: float) -> void:
	if not auto_tick:
		return
	_tick_timer += delta
	if _tick_timer >= tick_interval:
		_tick_timer = 0.0
		tick(tick_interval)

func tick(delta: float) -> void:
	_tick_count += 1
	if chemistry and world_grid:
		chemistry.step(delta, world_grid)
	_update_population_counts()
	var stats := get_stats()
	tick_completed.emit(_tick_count, stats)

func _update_population_counts() -> void:
	var counts: Dictionary = {}
	var creatures := get_tree().get_nodes_in_group("creatures") if get_tree() else []
	for c in creatures:
		var species: String = c.get("species_id") if "species_id" in c else "unknown"
		counts[species] = counts.get(species, 0) + 1
	# detect extinctions
	for species in _population.keys():
		if not counts.has(species) and _population[species] > 0:
			species_extinct.emit(species)
	_population = counts
	for species in _population.keys():
		population_changed.emit(species, _population[species])

func get_stats() -> Dictionary:
	return {
		"tick": _tick_count,
		"population": _population.duplicate(),
		"total_creatures": _population.values().reduce(func(a, b): return a + b, 0) if not _population.is_empty() else 0,
		"grid_cells": (WorldGrid.GRID_WIDTH * WorldGrid.GRID_HEIGHT) if world_grid else 0,
	}

func spawn_creature(scene: PackedScene, grid_pos: Vector2i) -> Node:
	if scene == null or world_grid == null:
		return null
	var instance: Node = scene.instantiate()
	get_tree().current_scene.add_child(instance)
	if instance is Node2D:
		(instance as Node2D).global_position = world_grid.grid_to_world(grid_pos)
	elif instance is Node3D:
		var pos2d := world_grid.grid_to_world(grid_pos)
		(instance as Node3D).global_position = Vector3(pos2d.x, 0.0, pos2d.y)
	instance.add_to_group("creatures")
	return instance

func get_population(species: String) -> int:
	return _population.get(species, 0)

func reset_simulation() -> void:
	_tick_count = 0
	_population.clear()
	if world_grid:
		world_grid._initialize_grid()
