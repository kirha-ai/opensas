# SJPI support: isolated half-grid follow-up

Status: IN PROGRESS, not full SJPI acceptance. Parent evidence landed at
4d061f4. This follow-up fixes the mathematical variant/pilot/search already
established there; it does not repeat bandwidth-formula fitting.

## Callable numerical core

`src/stat/univ_kernel_sjpi.zig` exports `BinnedSample`, `Result`, and `fromBins`.
Input: 201 integer bin counts, physical bin spacing, ORIGINAL n-1 sample SD,
and IQR. Output: physical h, standardized c, and root/maximum-fallback status.
It computes the pilots using the binned population variance. Derivative sums
use bin-spacing units to avoid powers of the physical measurement scale.
The original-unit absolute 0.001 stopping rule is preserved.

The helper deliberately does not accept a raw sample or guess its bin indices.
This is a useful independently testable part of the assigned numeric slice,
not an exclusion that makes raw-sample SJPI complete. No existing UNIV or PROC
module is edited, and the caller's unsupported SJPI guard remains necessary.

Five numerical test groups cover 23 actual SAS M9 bandwidth results: base,
affine/tiny units, small n and ties, outliers, fresh negative/positive translated
and scaled heldouts, plus ten no-bracket cases. A sixth test group checks
captured diagnostics for invalid/degenerate input. The heldout tests explicitly
supply the bin established by the oracle, not a purported raw binning rule.

`dev2-sjpi-binned-boundaries.{sas,txt,log}` has two synthetic frequency patterns
at each n=100/1000/10000/100000/1000000. All ten return the MAXIMUM search
bandwidth and emit a warning. The helper reproduces that behavior and exposes
the fallback status; it never silently substitutes MISE or widens the search.

## Discriminators and actual binary inputs

Every input value is supplied using HEX16. and printed back using HEX16.
`halfgrid.py` verifies those returned bits against the generated manifest.
For each sample it fixes all nonboundary bins and forces the one isolated
half-grid observation to its left and right candidate bins. The same frozen
formula/pilot/root solver is then compared with SAS's selected bandwidth.

Current retained batches:

| Stem after dev2-sjpi- | Cases | Purpose |
|---|---:|---|
| halfgrid | 24 | asymmetric sample, k=62/87, four domains, -1/0/+1 ULP |
| halfgrid-heldout | 28 | 12 fresh shifted/scaled cases; 16 ULP-transition probes |
| halfgrid-background | 12 | change other points, duplicate minimum, reverse order |
| halfgrid-background-left | 12 | repeat background controls at left-selecting boundaries |
| halfgrid-profile | 48 | 16 bin indices, each at -1/0/+1 ULP |
| halfgrid-zero | 12 | translate four positions to [0,16] |
| halfgrid-standalone | 9 | repeat selected BY cases as independent PROC invocations |
| halfgrid-arithmetic | 112 | native SAS hex intermediate arithmetic values |

The 136 isolated-point cases all uniquely match one forced assignment at
absolute h tolerance 1e-10 (maximum observed error 4.40536e-13). This establishes
which candidate bin explains each result, but is not itself a generic binning
algorithm. The 9 standalone results agree with their corresponding BY results.

The first 52 cases comprise the initial bounded discovery/heldout pass. After
the user explicitly requested continued work, the background/profile/zero and
native-arithmetic controls narrowed additional hypotheses. No additional
distribution-family, parser, rendering, or unrelated work is included.

## Concrete observations

- In [-8,8], k=62 is assigned right at -2 ULP from its mathematical midpoint
  and left at -4 ULP. For k=87 in the shifted [-7.99,8.01] domain, -4 ULP is
  still right and -8 ULP is left. These are not ordinary exact-tie-only effects.
- The background controls preserve the decision despite changing other points,
  the sample SD/IQR, multiplicity and input order. Standalone PROC invocations
  preserve it as well. These controls do not support a BY-state explanation.
- The zero-origin controls preserve the same index-dependent classifications;
  the problem cannot be attributed merely to subtracting a negative minimum.
- The 112 SAS arithmetic rows reproduce the ordinary binary64 Python step,
  reciprocal, centered value, division, inverse multiplication, scalar grid
  point, and distance intermediates BIT FOR BIT. The remaining discrepancy is
  in UNIVARIATE's binning path, not in the DATA-step expressions used to create
  or inspect the oracle inputs.
- Division versus inverse multiplication, absolute versus centered operations,
  fused versus separate midpoint evaluation, nearest distance, half-up versus
  ties-even, repeated edges/centers, and centered reconstruction all have
  retained counterexamples. The discovery-best centered-reconstruction/FMA
  candidate gets 21/24 discovery cases, 11/12 fresh heldouts, and only 93/136
  overall. It is NOT a validated algorithm.

Additional offline evaluations of interpolation order, strided/anchored grid
accumulation, padding, recursive/progressive grid generation, IEEE rounding
modes and squared-distance formulations did not establish a passing rule.
They are rejected hypotheses, not adjustable constants in the implementation.

## Run and interpret

```
python3 docs/findings/univ-sjpi-dev2/halfgrid.py
python3 docs/findings/univ-sjpi-dev2/halfgrid.py --require-parity
/Users/thomas/.local/bin/zig test src/root.zig --test-filter 'UNIV SJPI'
```

The default Python exit 0 means all forced-assignment comparisons are uniquely
resolved, not that SJPI is accepted. `--require-parity` exits 1 while every raw
arithmetic candidate has counterexamples. The Zig tests validate `fromBins`,
not the missing raw-observation selector. No existing expected-output golden
is changed. Raw SAS logs retain their original whitespace.

The unresolved mechanism is the exact mapping from IEEE64 input and domain
limits to UNIVARIATE's internal bin index. Never encode the observed decisions
as a table, loosen the tolerance, or activate SJPI using the best failing rule.
