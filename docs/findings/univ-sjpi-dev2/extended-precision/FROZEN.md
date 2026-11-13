# Preregistered normalized-coordinate / extended-precision pass

Baseline: dev2/main 8c17e8154953bb36e2c7751a2e50edbd2c31cb86.
Scope: raw bin decision only. Keep the existing SJPI formula, pilot, search,
stopping rule and accepted binned core unchanged. Do not enable public SJPI.

This file, simulator and heldout manifest are committed BEFORE evaluating the
candidate family against the 136 known assignments or running fresh SAS data.

## Frozen candidate family: 90 models

Five real-arithmetic-equivalent normalized-coordinate expressions, with
span=high-low, a=x-low, step=span/200 and inverse=1/step:

1. center_div: a/step
2. center_normalize: (a/span)*200
3. center_inverse: a*inverse
4. absolute_div: x/step-low/step
5. absolute_inverse: x*inverse-low*inverse

Six storage plans (explicit rounding to nearest, ties to even):

- binary64: round every arithmetic operation to 53 significand bits.
- extended64: retain 64 significand bits throughout.
- extended64_step_store: retain 64 bits but store step as binary64.
- extended64_input_store: retain 64 bits but store span, a, step and inverse
  as binary64 at their named definitions.
- extended64_q_store: retain 64 bits, store completed q as binary64.
- extended64_each_store: round each operation to 64 bits, then store its
  result as binary64 (explicit double-rounding model).

Three conversions, all independent of observed assignments:

- trunc_after_half: add 1/2 at the plan's arithmetic precision, then truncate
  directly to an integer (positive coordinates).
- spill_half_then_trunc: additionally store that sum as binary64 immediately
  before truncation.
- nearest_even: convert q directly to nearest integer, ties to even.

No fitted epsilon or index-specific constant is allowed. Apparent tolerance
near q+1/2 must arise solely from these explicit machine rounding/conversion
operations. No expression, spill point or conversion will be added after
scores or heldout outcomes are examined in this pass.

## Exact arithmetic model and limits

Python Fraction computes each operation exactly before explicit binary
rounding. The 64-bit significand corresponds to x87 double-extended precision;
53 bits corresponds to double precision. This is not evidence that SAS uses
x87, nor an emulation of unspecified register allocation or exception state.
The tested arithmetic uses finite, normal-range operands; exponent-range,
subnormal and exception differences are not exercised.

Before classification, validate normal-range binary64 arithmetic against all
1120 retained SAS HEX16 intermediate values and exact midpoint/double-rounding
self-tests. DATA-step agreement validates the simulator's binary64 baseline,
not internal C precision or conversion behavior.

Primary format reference: Intel SDM Volume 1, Chapter 8 (x87 precision control):
https://cdrdv2-public.intel.com/843827/253665-sdm-vol-1-dec-24.pdf

## Known cases and normalized ULP analysis

Use ALL 136 existing isolated-point assignments, with their actual SAS input
bits. Report exact q=200*(x-low)/(high-low), its displacement from k+1/2 in
binary64 and 64-significand ULPs, and selected evaluated-coordinate values.
Check for identical normalized coordinates (and identical centered operands)
with contradictory oracle assignments. Such a witness rules out a rule based
solely on that coordinate/index; it does not rule out absolute-coordinate
evaluation, unknown C expression order or all possible extended-precision use.

## Prespecified fresh heldouts: 27

Indices: 19, 83, 161 (not used in the previous profile).
Domains: [-2.125,9.875], [257.25,297.25], [-33.7,-30.74].
Background grid indices: 0,9,37,68,111,173,200.
For each index/domain, take the nearest binary64 value to the exact rational
half-grid location and its immediate lower/upper binary64 neighbors.
These are three physical representable values; their ACTUAL normalized ULP
spacings must be reported rather than assumed to equal one normalized ULP.

No reselection of cases is allowed. Supply and retrieve HEX16 input values;
infer the target's bin by forcing left/right assignments with the frozen
reference core. If both or neither explain the bandwidth at 1e-10 absolute h
tolerance, report the probe as unresolved rather than inventing a label.

## Acceptance and stopping

A candidate is eligible only if it passes all 136 known cases AND all uniquely
resolved fresh heldouts, with none unresolved. If none passes, conclude this
bounded expression/storage/conversion family is insufficient, retain explicit
counterexamples and the normalized-coordinate collision witnesses, and report
the core separately from the still-unaccepted raw selector. Do not continue
blind arithmetic fanout or insert the best failing rule into a public path.
