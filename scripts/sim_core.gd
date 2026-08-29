class_name SimCore
extends RefCounted

## Scene-tree-free simulation core (Phase 0 extraction — increment 1).
## Pure math only: no Node references, no get_tree(), no _process.
## Every function here must be headless-testable (see tests/unit/).
## WorldGrid delegates to these functions; values are unchanged.
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
