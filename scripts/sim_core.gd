class_name SimCore
extends RefCounted

## Scene-tree-free simulation core.
## Pure state transforms only: no Node references, no get_tree(), no _process.
## Every function here is headless-testable (see tests/unit/).
## WorldGrid owns presentation and delegates simulation math to this class.
##
## Extraction protocol (sprint plan, checkpoint #2): port line-for-line,
## then let the golden master (tests/golden/) prove behavior is preserved.


## Plants grow best at ~25 C (298 K), moderate moisture, high nutrients.
## Ported verbatim from WorldGrid._calc_growth_potential (gm-baseline).
static func calc_growth_potential(temp: float, moist: float, nutr: float) -> float:
	var temp_factor := 1.0 - absf(temp - 298.0) / 30.0
	temp_factor = clampf(temp_factor, 0.0, 1.0)

	var moist_factor := 1.0 - absf(moist - 0.5) * 2.0
	moist_factor = clampf(moist_factor, 0.0, 1.0)

	return temp_factor * moist_factor * nutr


## Advances heat and water by one tick without mutating the input arrays.
## Returns replacement `temperature` and `moisture` arrays.
static func simulate_thermodynamics(
		current_temperature: PackedFloat32Array,
		current_moisture: PackedFloat32Array,
		elevation: PackedFloat32Array,
		grid_width: int,
		grid_height: int,
		ambient_temp: float,
		solar_intensity: float,
		heat_diffusion_rate: float,
		evaporation_rate: float,
		rainfall_rate: float,
) -> Dictionary:
	var new_temp := current_temperature.duplicate()
	var new_moisture := current_moisture.duplicate()

	for y in range(1, grid_height - 1):
		for x in range(1, grid_width - 1):
			var idx := _idx(x, y, grid_width)

			# --- Heat Diffusion (Fourier's Law, simplified) ---
			var neighbor_avg := (
				current_temperature[_idx(x - 1, y, grid_width)]
				+ current_temperature[_idx(x + 1, y, grid_width)]
				+ current_temperature[_idx(x, y - 1, grid_width)]
				+ current_temperature[_idx(x, y + 1, grid_width)]
			) * 0.25

			new_temp[idx] += (neighbor_avg - current_temperature[idx]) * heat_diffusion_rate

			# Solar heating (stronger at low elevation)
			new_temp[idx] += solar_intensity * (1.0 - elevation[idx]) * 0.1

			# Radiative cooling toward ambient
			new_temp[idx] += (ambient_temp - current_temperature[idx]) * 0.001

			# --- Moisture Dynamics ---
			# Evaporation: hot + wet = steam
			if current_temperature[idx] > 310.0 and current_moisture[idx] > 0.1:
				var evap := evaporation_rate * (current_temperature[idx] - 310.0) / 60.0
				new_moisture[idx] -= evap
				new_temp[idx] -= evap * 50.0  # Evaporative cooling!

			# Rainfall: cool + humid areas get rain
			if current_temperature[idx] < 290.0 and current_moisture[idx] > 0.3:
				new_moisture[idx] += rainfall_rate

			# Water flows downhill (simplified gravity)
			var lowest_neighbor := idx
			var lowest_elev := elevation[idx]
			for offset: Vector2i in [
				Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)
			]:
				var nx: int = x + offset.x
				var ny: int = y + offset.y
				var nidx: int = _idx(nx, ny, grid_width)
				if elevation[nidx] < lowest_elev and current_moisture[nidx] < current_moisture[idx]:
					lowest_elev = elevation[nidx]
					lowest_neighbor = nidx

			if lowest_neighbor != idx and current_moisture[idx] > 0.2:
				var flow := (current_moisture[idx] - current_moisture[lowest_neighbor]) * 0.01
				new_moisture[idx] -= flow
				new_moisture[lowest_neighbor] += flow

			new_moisture[idx] = clampf(new_moisture[idx], 0.0, 1.0)
			new_temp[idx] = clampf(new_temp[idx], 200.0, 600.0)

	return {
		"temperature": new_temp,
		"moisture": new_moisture,
	}


## Advances vegetation, combustion, and decomposition by one tick without
## mutating the input arrays. The current write order is intentionally retained
## for golden-master compatibility; Increment 3 will correct the stencil order.
static func simulate_ecosystem(
		current_temperature: PackedFloat32Array,
		current_moisture: PackedFloat32Array,
		current_biomass: PackedFloat32Array,
		current_nutrients: PackedFloat32Array,
		grid_width: int,
		grid_height: int,
		vegetation_growth_rate: float,
		combustion_threshold_temp: float,
		combustion_min_biomass: float,
		decomposition_rate: float,
) -> Dictionary:
	# The legacy algorithm writes heat and moisture into the live tick state,
	# while biomass and nutrients use replacement buffers. Work on private copies
	# to retain that ordering without leaking mutations through this pure API.
	var new_temp := current_temperature.duplicate()
	var new_moisture := current_moisture.duplicate()
	var new_biomass := current_biomass.duplicate()
	var new_nutrients := current_nutrients.duplicate()

	for y in range(1, grid_height - 1):
		for x in range(1, grid_width - 1):
			var idx := _idx(x, y, grid_width)

			# --- Combustion ---
			if (
				new_temp[idx] > combustion_threshold_temp
				and current_biomass[idx] > combustion_min_biomass
				and new_moisture[idx] < 0.2
			):
				# FIRE! Biomass converts to heat and nutrients (ash)
				var burn_amount := current_biomass[idx] * 0.1
				new_biomass[idx] -= burn_amount
				new_temp[idx] += burn_amount * 200.0  # Fire releases heat
				new_nutrients[idx] += burn_amount * 0.5  # Ash fertilizes
				new_moisture[idx] -= 0.05  # Fire dries the area

				# Fire spreads to neighbors
				for offset: Vector2i in [
					Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)
				]:
					var nidx: int = _idx(x + offset.x, y + offset.y, grid_width)
					if current_biomass[nidx] > 0.2 and new_moisture[nidx] < 0.3:
						new_temp[nidx] += 30.0

			# --- Growth ---
			elif current_biomass[idx] < 1.0:
				var potential := calc_growth_potential(
					new_temp[idx], new_moisture[idx], current_nutrients[idx]
				)
				if potential > 0.1:
					new_biomass[idx] += potential * vegetation_growth_rate

					# Growth consumes nutrients and water
					new_nutrients[idx] -= potential * 0.001
					new_moisture[idx] -= potential * 0.002

			# --- Decomposition ---
			if current_biomass[idx] > 0.0 and new_temp[idx] > 280.0:
				var decay := current_biomass[idx] * decomposition_rate
				if new_moisture[idx] > 0.3:
					decay *= 2.0  # Wet = faster rot
				new_biomass[idx] -= decay
				new_nutrients[idx] += decay * 0.8  # Nutrients return to soil

			new_biomass[idx] = clampf(new_biomass[idx], 0.0, 1.0)
			new_nutrients[idx] = clampf(new_nutrients[idx], 0.0, 1.0)

	return {
		"temperature": new_temp,
		"moisture": new_moisture,
		"biomass": new_biomass,
		"nutrients": new_nutrients,
	}


static func _idx(x: int, y: int, grid_width: int) -> int:
	return y * grid_width + x
