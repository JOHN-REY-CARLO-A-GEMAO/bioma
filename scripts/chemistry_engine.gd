class_name ChemistryEngine
extends Node
## Reaction-diffusion chemistry simulation.
## Operates over WorldGrid cells. Each cell holds a concentration map
## of named reagents. Call step(delta) from EcosystemSim or main loop.

@export var diffusion_rate: float = 0.12
@export var decay_rate: float = 0.01
@export var reaction_enabled: bool = true

var _concentrations: Dictionary = {}  # Vector3i -> Dictionary[String, float]
var _reactions: Array[Dictionary] = []

signal reaction_occurred(pos: Vector3i, reaction_id: String)

func _ready() -> void:
	_register_default_reactions()

func _register_default_reactions() -> void:
	# Example: A + B -> C
	_reactions = [
		{
			"id": "photosynthesis",
			"reactants": {"co2": 0.5, "water": 0.5},
			"products": {"glucose": 1.0, "o2": 0.8},
			"rate": 0.05,
			"requires_light": true,
		},
		{
			"id": "decomposition",
			"reactants": {"glucose": 1.0},
			"products": {"co2": 0.6, "nutrients": 0.8},
			"rate": 0.02,
		},
	]

func get_concentration(pos: Vector3i, reagent: String) -> float:
	var cell: Dictionary = _concentrations.get(pos, {})
	return cell.get(reagent, 0.0)

func set_concentration(pos: Vector3i, reagent: String, value: float) -> void:
	if not _concentrations.has(pos):
		_concentrations[pos] = {}
	_concentrations[pos][reagent] = maxf(0.0, value)

func add_concentration(pos: Vector3i, reagent: String, delta: float) -> void:
	set_concentration(pos, reagent, get_concentration(pos, reagent) + delta)

func step(delta: float, world_grid: WorldGrid) -> void:
	if world_grid == null:
		return
	_diffuse(delta, world_grid)
	if reaction_enabled:
		_react(delta, world_grid)
	_decay(delta)

func _diffuse(delta: float, world_grid: WorldGrid) -> void:
	var next: Dictionary = {}
	for pos in _concentrations.keys():
		var cell_conc: Dictionary = _concentrations[pos]
		for reagent in cell_conc.keys():
			var amount: float = cell_conc[reagent]
			if amount <= 0.001:
				continue
			var neighbors: Array[Vector3i] = world_grid.get_neighbors(pos, false)
			if neighbors.is_empty():
				continue
			var outflow := amount * diffusion_rate * delta / float(neighbors.size())
			for n in neighbors:
				if not next.has(n):
					next[n] = {}
				next[n][reagent] = next[n].get(reagent, 0.0) + outflow
			# subtract outflow from source (applied via next accumulation)
			if not next.has(pos):
				next[pos] = {}
			next[pos][reagent] = next[pos].get(reagent, 0.0) - outflow * neighbors.size()

	# merge diffusion delta
	for pos in next.keys():
		if not _concentrations.has(pos):
			_concentrations[pos] = {}
		for reagent in next[pos].keys():
			_concentrations[pos][reagent] = maxf(0.0, _concentrations[pos].get(reagent, 0.0) + next[pos][reagent])

func _react(delta: float, _world_grid: WorldGrid) -> void:
	for pos in _concentrations.keys():
		for reaction in _reactions:
			if _can_react(pos, reaction):
				_apply_reaction(pos, reaction, delta)

func _can_react(pos: Vector3i, reaction: Dictionary) -> bool:
	for reagent in reaction["reactants"].keys():
		if get_concentration(pos, reagent) < reaction["reactants"][reagent]:
			return false
	return true

func _apply_reaction(pos: Vector3i, reaction: Dictionary, delta: float) -> void:
	var rate: float = reaction["rate"] * delta
	for reagent in reaction["reactants"].keys():
		add_concentration(pos, reagent, -reaction["reactants"][reagent] * rate)
	for reagent in reaction["products"].keys():
		add_concentration(pos, reagent, reaction["products"][reagent] * rate)
	reaction_occurred.emit(pos, reaction["id"])

func _decay(delta: float) -> void:
	for pos in _concentrations.keys():
		for reagent in _concentrations[pos].keys():
			_concentrations[pos][reagent] = maxf(0.0, _concentrations[pos][reagent] - decay_rate * delta * 0.1)

func register_reaction(reaction: Dictionary) -> void:
	_reactions.append(reaction)

func clear_reagent(reagent: String) -> void:
	for pos in _concentrations.keys():
		_concentrations[pos].erase(reagent)
