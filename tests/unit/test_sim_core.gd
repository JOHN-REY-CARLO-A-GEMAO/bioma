# GdUnit4 suite — sprint increment 1 (checkpoints #1–2):
#   * harness proof          (cheap, pure boundary tests run first)
#   * extraction guard       (WorldGrid must delegate to SimCore, values identical)
#   * seed determinism lock  (same seed -> same world; different seed -> different world)
extends GdUnitTestSuite

const EPS := 0.0001

# --- calc_growth_potential: boundary contract ---

func test_optimum_at_298k_half_moisture_equals_nutrients() -> void:
	assert_float(SimCore.calc_growth_potential(298.0, 0.5, 0.7)).is_equal_approx(0.7, EPS)


func test_zero_at_temperature_band_edges() -> void:
	assert_float(SimCore.calc_growth_potential(268.0, 0.5, 1.0)).is_zero()
	assert_float(SimCore.calc_growth_potential(328.0, 0.5, 1.0)).is_zero()


func test_zero_beyond_temperature_band_clamped() -> void:
	assert_float(SimCore.calc_growth_potential(200.0, 0.5, 1.0)).is_zero()
	assert_float(SimCore.calc_growth_potential(400.0, 0.5, 1.0)).is_zero()


func test_zero_at_moisture_extremes() -> void:
	assert_float(SimCore.calc_growth_potential(298.0, 0.0, 1.0)).is_zero()
	assert_float(SimCore.calc_growth_potential(298.0, 1.0, 1.0)).is_zero()


func test_zero_nutrients_means_no_growth() -> void:
	assert_float(SimCore.calc_growth_potential(298.0, 0.5, 0.0)).is_zero()


# --- shape properties (behavior the tuning relies on) ---

func test_temperature_symmetry_around_optimum() -> void:
	var cold := SimCore.calc_growth_potential(288.0, 0.5, 1.0)
	var warm := SimCore.calc_growth_potential(308.0, 0.5, 1.0)
	assert_float(cold).is_equal_approx(2.0 / 3.0, EPS)
	assert_float(warm).is_equal_approx(cold, EPS)


func test_moisture_symmetry_around_optimum() -> void:
	var dry := SimCore.calc_growth_potential(298.0, 0.25, 1.0)
	var wet := SimCore.calc_growth_potential(298.0, 0.75, 1.0)
	assert_float(dry).is_equal_approx(0.5, EPS)
	assert_float(wet).is_equal_approx(dry, EPS)


func test_monotonic_in_nutrients() -> void:
	var low := SimCore.calc_growth_potential(298.0, 0.5, 0.2)
	var high := SimCore.calc_growth_potential(298.0, 0.5, 0.8)
	assert_float(high).is_greater(low)


func test_never_negative_for_wild_inputs() -> void:
	assert_float(SimCore.calc_growth_potential(1000.0, 5.0, -3.0)).is_zero()


# --- extraction guards ---

func test_world_grid_delegates_to_simcore() -> void:
	var wg := WorldGrid.new()
	assert_float(wg._calc_growth_potential(298.0, 0.5, 0.7)).is_equal_approx(
		SimCore.calc_growth_potential(298.0, 0.5, 0.7), EPS)
	wg.free()


# --- seed determinism (checkpoint #1) ---

func test_grid_init_allocates_every_cell() -> void:
	var wg := WorldGrid.new()
	wg._initialize_grid(1337)
	var cell_count: int = WorldGrid.GRID_WIDTH * WorldGrid.GRID_HEIGHT
	assert_int(wg.temperature.size()).is_equal(cell_count)
	assert_int(wg.moisture.size()).is_equal(cell_count)
	assert_int(wg.biomass.size()).is_equal(cell_count)
	assert_int(wg.nutrients.size()).is_equal(cell_count)
	assert_int(wg.elevation.size()).is_equal(cell_count)
	wg.free()


func test_grid_init_is_seed_reproducible() -> void:
	var a := WorldGrid.new()
	var b := WorldGrid.new()
	a._initialize_grid(1337)
	b._initialize_grid(1337)
	assert_that(a.elevation == b.elevation).is_true()
	assert_that(a.temperature == b.temperature).is_true()
	assert_that(a.moisture == b.moisture).is_true()
	assert_that(a.biomass == b.biomass).is_true()
	assert_that(a.nutrients == b.nutrients).is_true()
	a.free()
	b.free()


func test_different_seeds_produce_different_worlds() -> void:
	var a := WorldGrid.new()
	var b := WorldGrid.new()
	a._initialize_grid(1)
	b._initialize_grid(2)
	assert_that(a.elevation != b.elevation).is_true()
	a.free()
	b.free()


func test_seeded_reset_rebuilds_clean_buffers() -> void:
	var wg := WorldGrid.new()
	wg._initialize_grid(1337)
	var initial_temperature := wg.temperature.duplicate()
	var initial_moisture := wg.moisture.duplicate()
	var initial_biomass := wg.biomass.duplicate()
	var initial_nutrients := wg.nutrients.duplicate()
	var initial_elevation := wg.elevation.duplicate()

	wg._simulate_thermodynamics()
	wg._simulate_ecosystem()
	wg._initialize_grid(1337)

	assert_that(wg.temperature == initial_temperature).is_true()
	assert_that(wg.moisture == initial_moisture).is_true()
	assert_that(wg.biomass == initial_biomass).is_true()
	assert_that(wg.nutrients == initial_nutrients).is_true()
	assert_that(wg.elevation == initial_elevation).is_true()
	wg.free()
