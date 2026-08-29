# GdUnit4 suite — sprint increment 2 (SimCore adoption):
#   * thermodynamics is a pure, scene-tree-free state transform
#   * ecosystem growth/combustion math is independently testable
#   * WorldGrid is only an adapter around SimCore
extends GdUnitTestSuite

const EPS := 0.0001
const SMALL_WIDTH := 3
const SMALL_HEIGHT := 3
const CENTER := 4


func test_thermodynamics_diffuses_heat_without_mutating_inputs() -> void:
	var temperature := _filled(9, 293.0)
	temperature[CENTER] = 303.0
	var moisture := _filled(9, 0.5)
	var elevation := _filled(9, 1.0)
	var original_temperature := temperature.duplicate()
	var original_moisture := moisture.duplicate()

	var result := SimCore.simulate_thermodynamics(
		temperature,
		moisture,
		elevation,
		SMALL_WIDTH,
		SMALL_HEIGHT,
		293.0,
		0.3,
		0.02,
		0.005,
		0.001,
	)

	# Four 293 K neighbors cool the 303 K center by 0.2 K; radiation
	# contributes another 0.01 K. Unit elevation suppresses solar heating.
	assert_float(result["temperature"][CENTER]).is_equal_approx(302.79, EPS)
	assert_float(result["temperature"][0]).is_equal_approx(293.0, EPS)
	assert_float(result["moisture"][CENTER]).is_equal_approx(0.5, EPS)
	assert_that(temperature == original_temperature).is_true()
	assert_that(moisture == original_moisture).is_true()


func test_thermodynamics_applies_evaporation_and_rainfall() -> void:
	var temperature := _filled(9, 293.0)
	var moisture := _filled(9, 0.5)
	var elevation := _filled(9, 1.0)

	temperature[CENTER] = 340.0
	var hot_result := SimCore.simulate_thermodynamics(
		temperature, moisture, elevation,
		SMALL_WIDTH, SMALL_HEIGHT,
		340.0, 0.0, 0.0, 0.005, 0.001,
	)
	assert_float(hot_result["moisture"][CENTER]).is_equal_approx(0.4975, EPS)
	assert_float(hot_result["temperature"][CENTER]).is_equal_approx(339.875, EPS)

	temperature[CENTER] = 280.0
	var cool_result := SimCore.simulate_thermodynamics(
		temperature, moisture, elevation,
		SMALL_WIDTH, SMALL_HEIGHT,
		280.0, 0.0, 0.0, 0.005, 0.001,
	)
	assert_float(cool_result["moisture"][CENTER]).is_equal_approx(0.501, EPS)


func test_ecosystem_growth_consumes_water_and_nutrients() -> void:
	var temperature := _filled(9, 298.0)
	var moisture := _filled(9, 0.5)
	var biomass := _filled(9, 0.0)
	var nutrients := _filled(9, 0.7)
	biomass[CENTER] = 0.2
	var original_moisture := moisture.duplicate()
	var original_biomass := biomass.duplicate()
	var original_nutrients := nutrients.duplicate()

	var result := SimCore.simulate_ecosystem(
		temperature,
		moisture,
		biomass,
		nutrients,
		SMALL_WIDTH,
		SMALL_HEIGHT,
		0.002,
		373.0,
		0.3,
		0.0,
	)

	assert_float(result["biomass"][CENTER]).is_equal_approx(0.2014, EPS)
	assert_float(result["nutrients"][CENTER]).is_equal_approx(0.6993, EPS)
	assert_float(result["moisture"][CENTER]).is_equal_approx(0.4986, EPS)
	assert_that(moisture == original_moisture).is_true()
	assert_that(biomass == original_biomass).is_true()
	assert_that(nutrients == original_nutrients).is_true()


func test_ecosystem_combustion_converts_biomass_and_spreads_heat() -> void:
	var temperature := _filled(9, 300.0)
	var moisture := _filled(9, 0.1)
	var biomass := _filled(9, 0.3)
	var nutrients := _filled(9, 0.2)
	temperature[CENTER] = 400.0
	biomass[CENTER] = 0.5

	var result := SimCore.simulate_ecosystem(
		temperature,
		moisture,
		biomass,
		nutrients,
		SMALL_WIDTH,
		SMALL_HEIGHT,
		0.002,
		373.0,
		0.3,
		0.0,
	)

	assert_float(result["biomass"][CENTER]).is_equal_approx(0.45, EPS)
	assert_float(result["temperature"][CENTER]).is_equal_approx(410.0, EPS)
	assert_float(result["nutrients"][CENTER]).is_equal_approx(0.225, EPS)
	assert_float(result["moisture"][CENTER]).is_equal_approx(0.05, EPS)
	for neighbor_idx in [1, 3, 5, 7]:
		assert_float(result["temperature"][neighbor_idx]).is_equal_approx(330.0, EPS)


func test_world_grid_adopts_both_simcore_steps() -> void:
	var wg := WorldGrid.new()
	var cell_count: int = WorldGrid.GRID_WIDTH * WorldGrid.GRID_HEIGHT
	wg.temperature = _filled(cell_count, 293.0)
	wg.moisture = _filled(cell_count, 0.5)
	wg.biomass = _filled(cell_count, 0.2)
	wg.nutrients = _filled(cell_count, 0.4)
	wg.elevation = _filled(cell_count, 0.5)

	var expected_thermo := SimCore.simulate_thermodynamics(
		wg.temperature,
		wg.moisture,
		wg.elevation,
		WorldGrid.GRID_WIDTH,
		WorldGrid.GRID_HEIGHT,
		wg.ambient_temp,
		wg.solar_intensity,
		wg.heat_diffusion_rate,
		wg.evaporation_rate,
		wg.rainfall_rate,
	)
	wg._simulate_thermodynamics()
	assert_that(wg.temperature == expected_thermo["temperature"]).is_true()
	assert_that(wg.moisture == expected_thermo["moisture"]).is_true()

	var expected_ecosystem := SimCore.simulate_ecosystem(
		wg.temperature,
		wg.moisture,
		wg.biomass,
		wg.nutrients,
		WorldGrid.GRID_WIDTH,
		WorldGrid.GRID_HEIGHT,
		wg.vegetation_growth_rate,
		wg.combustion_threshold_temp,
		wg.combustion_min_biomass,
		wg.decomposition_rate,
	)
	wg._simulate_ecosystem()
	assert_that(wg.temperature == expected_ecosystem["temperature"]).is_true()
	assert_that(wg.moisture == expected_ecosystem["moisture"]).is_true()
	assert_that(wg.biomass == expected_ecosystem["biomass"]).is_true()
	assert_that(wg.nutrients == expected_ecosystem["nutrients"]).is_true()
	wg.free()


func _filled(size: int, value: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(size)
	result.fill(value)
	return result
