extends SceneTree
## Golden-master harness for the grid simulation (sprint plan protocol:
## "capture, measure, then re-derive"). Diagnostic tool — NOT a unit test.
##
##   capture:  godot --headless --path . -s res://tests/golden/golden_master_runner.gd -- capture
##   compare:  godot --headless --path . -s res://tests/golden/golden_master_runner.gd -- compare
##
## Exit codes (compare mode): 0 = matches baseline, 1 = diverged, 2 = baseline missing.
##
## The baseline file IS committed. Contract:
##   * Increment 2 (SimCore adoption of thermo/ecosystem) must keep compare GREEN.
##   * Increment 3 (stencil write-order fix) is EXPECTED to diverge: re-capture,
##     and paste this script's expected/actual report into that PR description.
##
## Note: array hashes are compared exactly — valid for the same binary and
## platform (linux x86_64 CI). Other platforms: regenerate locally for local
## comparisons; do not commit cross-platform baselines.

const SEED := 1337
const TICKS := 200
const DIR := "res://tests/golden"
const KEYS := ["temperature", "moisture", "biomass", "nutrients", "elevation"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "compare"

	var wg = load("res://scripts/world_grid.gd").new()
	wg._initialize_grid(SEED)
	for i in TICKS:
		wg._simulate_thermodynamics()
		wg._simulate_ecosystem()

	var report := "seed=%d ticks=%d\n" % [SEED, TICKS]
	for key in KEYS:
		var arr: PackedFloat32Array = wg.get(key)
		report += "%s hash=%d mean=%.6f min=%.3f max=%.3f\n" % [
			key, arr.hash(), _mean(arr), _min(arr), _max(arr)
		]
	wg.free()

	var path := "%s/baseline_seed%d_t%d.txt" % [DIR, SEED, TICKS]
	match mode:
		"capture":
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(report)
			f.close()
			print("CAPTURED -> %s" % path)
			print(report)
			quit(0)
		"compare":
			if not FileAccess.file_exists(path):
				printerr("Baseline missing: %s" % path)
				printerr("Run capture mode and commit the file.")
				quit(2)
				return
			var baseline := FileAccess.get_file_as_string(path)
			if baseline.strip_edges() == report.strip_edges():
				print("GOLDEN MASTER OK — grid state matches baseline (%s)" % path)
				quit(0)
			else:
				printerr("GOLDEN MASTER DIVERGED vs %s" % path)
				printerr("--- expected ---\n%s" % baseline)
				printerr("--- actual ---\n%s" % report)
				quit(1)
		_:
			printerr("Unknown mode: %s (use capture|compare)" % mode)
			quit(2)


func _mean(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / float(a.size())


func _min(a: PackedFloat32Array) -> float:
	var m := a[0]
	for v in a:
		if v < m:
			m = v
	return m


func _max(a: PackedFloat32Array) -> float:
	var m := a[0]
	for v in a:
		if v > m:
			m = v
	return m
