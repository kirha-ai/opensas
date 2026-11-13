# Frozen absolute-grid discriminator

Initial baseline: d29469d2cb5d9ffbaa108c3330a0532e713e8cd4.
Only the raw-selector mechanism is investigated. The accepted fromBins core,
SJPI formula/pilots/root search, original normalization and public guard stay
unchanged. No q-only tolerance or x87 storage family is rerun.

## Family: 12 center generators x 6 decisions = 72 configurations

N=200 intervals. Endpoints G[0]=low and G[N]=high are assigned directly.
Each interior center is rounded/stored as binary64 BEFORE any decision.

Six barycentric generators, evaluated in the exact order in grids.py:

1. (1-t)*low+t*high, t=i/N, separate products/addition.
2. fma(1-t, low, t*high).
3. fma(t, high, (1-t)*low).
4. ((N-i)*low+i*high)/N.
5. fma(N-i, low, i*high)/N.
6. fma(i, high, (N-i)*low)/N.

These six were considered in the earlier partial offline interpolation audit.
Their existing counterexamples are NOT discarded. Here they are reproduced
against the full 163 fixed assignments, with explicit stored-center semantics.
The ordinary sum-midpoint/distance configurations are rechecks, not discoveries.

Six two-ended/symmetric constructions, not previously retained as this complete
163-case family (step=(high-low)/N, M=(low+high)/2):

7. Generate i<100 from low+i*step; i>100 from high-(N-i)*step; G[100]=M.
8. Same two-ended construction using FMA on each side; G[100]=M.
9. Accumulate inward from both endpoints for 99 steps; set G[100]=M.
10. M+(i-100)*step, separate multiplication/addition.
11. fma(i-100, step, M).
12. Generate left centers low+i*step; reflect each as (low+high)-G[i];
    G[100]=M. The sum low+high is stored once before reflections.

Six decisions for adjacent stored centers a=G[k], b=G[k+1]:

- Compare raw x with (a+b)/2, with right or left chosen on equality.
- Compare raw x with a+(b-a)/2, with right or left chosen on equality.
- Compare rounded absolute distances abs(x-a), abs(b-x), with right or left
  chosen on equality. No epsilon or measured threshold enters a decision.

FMA is correctly rounded to binary64 using exact rational multiplication and
addition, reusing only the previous round-to-nearest/even primitive. There is
no extended-precision expression/storage search in this pass.

## Offline phase

Revalidate and keep ALL 163 known assignments (previous 136 + prespecified 27).
Evaluate the fixed family once. Save complete failed-case indices and explicit
old counterexamples with both stored-center bit patterns. All configurations
must pass all 163 before any can be called viable.

## Conditional oracle phase

If any configuration passes all 163, validate without changing it on 27 fresh
cases: indices 43/109/181; domains [-5.125,10.875], [19.2,25.6],
[-101.5,-69.5]; background indices 0/9/37/68/111/173/200; exact rational
half-point rounded to binary64 and its immediate lower/upper neighbors.
Do not accept a candidate with any old or fresh mismatch or unresolved probe.

If none is viable, execute ONLY this threshold search:

- Adjacent indices 86/87/88 in each translated collision domain [-8,8] and
  [-7.99,8.01]: exactly six target/domain combinations.
- Background indices 0/13/34/55/106/152/200, as in the collision experiment.
- Origin of each search is the nearest binary64 value to the EXACT rational
  half-point low+(high-low)*(k+1/2)/N.
- First probe -32 and +32 representable binary64 rank steps. If they do not
  bracket left/right, report unresolved; do not enlarge the bracket.
- With bracketed results, at most six binary-search rounds probe the integer
  midpoint rank per target, until last-left and first-right are adjacent.
- Final independent batch probes L-1, L, R, R+1 for each target. Verify the
  repeated assignments and local 0,0,1,1 order. This may reach offset +/-33.
- Every observation is supplied and recovered as HEX16. Infer each assignment
  from two forced-bin bandwidths, using the frozen reference core at 1e-10
  absolute h tolerance. Ambiguity, nonmonotonic sampled labels or inconsistent
  repeat results stop the pass; no case replacement or tolerance adjustment.

Maximum threshold budget: 12 endpoint + 36 bisection + 24 verification = 72
SAS sample groups, in at most 8 batches. The source for each query is retained.
Adaptive midpoint choices depend only on the fixed binary-search algorithm
and observed labels, not on which candidate formula looks promising.

## Fingerprints and stop rule

Retain exact last-left/first-right HEX values, representable ranks, normalized
ULP offsets, and all oracle/candidate bandwidths. Compare frozen-model
transitions with the measured transitions; report adjacent-index recurrence
residuals and translated-domain residuals, in exact values and binary64 ranks.
These are diagnostic fingerprints, NEVER a runtime lookup table.

If the family fails, report the precise remaining obstruction and stop this
bounded pass. Do not append arithmetic combinations or index-specific constants
after seeing the oracle. The core and public raw-selector status are separate.
