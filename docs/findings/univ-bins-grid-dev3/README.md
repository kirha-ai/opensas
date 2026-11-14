# FEAT-univ-distributions — dev3 bin/grid support checkpoint

Scope: owned `univ_histogram_bins.zig`, `univ_kernel_output.zig`, new numerical
`univ_histogram_output.zig` and `univ_kernel_grid.zig`, fixtures and evidence.
No endpoint solver changes, graphics implementation, parser/statement/PROC edits,
or parent-ticket completion claim. Initial clean claim baseline: 5117820.

## Additive no-render contract

Existing `automatic(...)`, `kernel_output.create(...)` and `append(...)` entry
points remain source-compatible. All samples are finite, sorted, missing-filtered
and FREQ-expanded by the caller. BY/CLASS formatting and statement/output-option
precedence remain with dev4. Helpers allocate in caller arenas and return typed
boundaries, bins, datasets or captured diagnostics; they do not render or publish.

- `binning.determine(allocator, diagnostics, cells, Request)` returns a Plan with
  boundaries, nominal width, cell order, constant value, empty-key fallback and
  window-clipping flags. Request defaults preserve KEY/first-cell behavior;
  optional `mode`, `key_index`, `key_move`, `target_count`, `max_nbin` and
  `max_sigmas` expose numerical controls without implementing CLASS parsing.
  Empty resolved keys warn and use pooled UNIFORM data. Unknown key labels must
  be resolved by the caller, not fabricated into indices. Count targets below
  two warn and revert to automatic selection. Window limits preserve the initial
  key range and extend in cell order; clipped output keeps full-cell denominators.
- `binning.cover(...)` validates an explicit equally spaced boundary list and
  extends it with a warning, including a value on its open endpoint.
- `histogram_output.create/append/bins` own numeric OUTHISTOGRAM schema and row
  construction. Options select endpoint/midpoint labels, right inclusion,
  curve columns, maximum variable-name length, nominal bin width and clipping.
  Supply Plan.width rather than reconstructing it by subtracting large adjacent
  coordinates. Constant parametric-curve groups retain blank curve names and
  missing expected percentages. Ordered keys copy their original descriptors.
- `kernel_output.appendBatch(...)` fits the requested bandwidths once and shares
  the largest padded grid. An empty request list means the default normal MISE
  kernel, as OUTKERNEL alone does in M9. Options.automatic selects automatic
  extent, Options.windowed respects a limited histogram window, and bin_width
  carries the nominal width. Common bounds round to histogram lattice limits;
  different bounds retain the shared grid and zero each curve outside its bounds.
- `appendEstimates(...)` accepts already fitted estimates, so another estimator
  can supply a bandwidth without this layer changing or refitting its method.
- `fitForOutput(...)` implements the observed zero-IQR fallback (range, or one
  for a constant sample), including one observation. MISE C is rounded to eight
  significant digits as in the M9 output/evaluation. Scalar `kernel.fit` is not
  modified by this slice.
- Optional `Report` gives point_count and compact_cutoff_unverified. The latter
  is deliberately true for compact kernels while the three discrepancies below
  remain. Legacy append treats supplied boundaries as authoritative; callers
  needing automatic/shared extent must migrate to appendBatch and consume the
  report. It is not an acceptance waiver to retain an approximate curve.

The allocation/axis stepping budgets are explicit numerical resource limits,
not undocumented SAS options. Invalid spacing, nonfinite inputs, incompatible
window controls and unrepresentable grids fail through captured diagnostics.

## Numerical behavior established by actual SAS M9

Local cited manual: Statistical Procedures pp.320–322 (key cells), 333 and
337–341 (histogram controls), 462–463 (output datasets). The oracle source and
raw output/log triplets in this directory use unique absolute dev3 paths:

    /Users/thomas/sas/bin/sasrun /Users/thomas/kirha/opensas-dev3/docs/findings/univ-bins-grid-dev3/NAME.sas -f text -o /Users/thomas/kirha/opensas-dev3/docs/findings/univ-bins-grid-dev3/NAME.txt -l /Users/thomas/kirha/opensas-dev3/docs/findings/univ-bins-grid-dev3/NAME.log

- Constant bins use width abs(value), or one at zero. KEY keeps that width and
  extends the key lattice; UNIFORM pools counts/range first. Midpoint phases
  choose between the two half-width lattices. Count controls choose nice axis
  values, not necessarily the literal requested number of occupied bins.
- MAXNBIN/MAXSIGMAS affect saved numerical rows, not just a picture. Outside
  observations do not renormalize percentages. Fully excluded cells retain
  zero-count boundary rows; samples spanning both sides can retain zero rows
  across the window. ENDPOINTS controls count the endpoint list itself.
- OUTHISTOGRAM trims unoccupied outer bins, preserves interior empty bins,
  uses _MINPT_/_MAXPT_ for endpoint labels, and includes _CURVE_/_EXPPCT_ only
  for requested parametric curves. Kernel-only output has no curve columns.
- OUTKERNEL uses the 128-interval data lattice with a padded finite Fourier
  convolution. Output can include duplicate interpolated boundary rows; it
  cannot include coordinates beyond its native padded lattice. Gaussian,
  quadratic and triangular characteristic functions provide the spectral
  ordinates. Reflection and compact support masks are separate from extent.
- Kernel grids share the largest period/padding across bandwidths. The f36b582
  Request.fft_period/Estimate.fftPeriod handoff is integrated after rebasing onto
  f36b582. Nonconstant batches use the largest Estimate.fftPeriod; explicit
  period hints must be two or four data ranges or fail visibly; zero-range fallback remains this output helper's responsibility.
- Constants use an artificial unit data range for the kernel lattice, but the
  histogram width for vertical scaling. Constant FFT padding depends on the
  point-mass span, not the artificial data span. The constant center lattice
  retains SAS's iterative endpoint rounding.
- Empty/all-missing inputs keep declared empty output schemas. _VAR_ length is
  max(8, selected-name lengths), even for a selected all-missing long variable.
  BY/CLASS length, format, informat and label are preserved; analysis-variable
  formats are not transferred onto the fixed numeric output fields. Dataset
  labels are Histogram Statistics and Kernel Density Estimates.

## Verification and gaps

The histogram fixture retains **833 independently generated rows** for KEY,
UNIFORM, empty/constant keys, count targets, endpoint inclusion, ties, window
limits and reversed class order. They match at 1e-9 absolute tolerance (counts
are logically exact; M9 itself sometimes stores 6 as 5.999999999999999).

The kernel fixture retains **10,085 rows** across discovery and independent
heldouts, three kernels, multiple C values, common/different bounds, explicit
and automatic extents, all three vertical scales, one-point/constant samples,
zero IQR and default MISE. Grid coordinates, order, C/type and row counts are
checked. Normal densities and the other matching densities use 1e-9 tolerance.

Three compact-cutoff density discrepancies are **not accepted as equality**:

| Case / row | SAS density | Current density |
|---|---:|---:|
| reflected2 / 160 | .11022133164670005 | .11021116511244002 |
| held3 / 5 | 0 | .000010784923182808298 |
| held3 / 251 | .000010011126091058475 | 0 |

The unchanged oracle values and a separate gap ledger remain in testdata.
The test checks the three known witnesses and rejects any unrecorded discrepancy;
it does not loosen the density tolerance or call these matching rows. Fourier
values away from the compact cutoff agree closely, but the exact SAS zero-mask
rounding is unresolved. Prefix/full-grid controls falsified a simple output-row
shift explanation. Report.compact_cutoff_unverified exposes the limitation.

`tests/corpus/univ_bins_constant_dev3.sas` is a real public no-render regression
with an independently generated M9 golden: BY groups, three location-label
modes and five constant values. Additional public wiring is handed to dev4:
per-BY/per-variable shared planning, typed named/count controls, variable-first
cell output order, batch grids/default OUTKERNEL, and constant curve suppression.
These are not claimed active merely because helper tests are green.

The owned kernel period handoff's x=(6,8), C=.5 regression verifies that value 2
is absent and density at 4 agrees with .01637919. Period hints must remain
consistent with output lattice extent. Final branch/base/HEAD and complete gate
counts are reported at handoff; the parent ticket remains open.

Probe caveats are retained honestly: `grid-boundaries` contains an accidental
empty KERNEL() syntax error; the valid omitted/default kernel is independently
covered by `extra-controls`. `window-order` intentionally tests incompatible and
nonpositive controls (SAS errors); its empty-array dump warnings are probe
instrumentation. The first window-controls connection failed before a SAS job
started; the retained rerun succeeded. No failed run is called a clean fit.

## Recovery checkpoint verification (2026-11-14)

All pre-existing tracked and untracked helper work was checkpointed before a
conflict-free local rebase onto f36b58200891b3376b6c6f93637d1279a72e6698.
The two fixture export scripts reproduced the expected files byte-for-byte from
the retained actual SAS logs (833 histogram and 10,085 kernel rows). A fresh run
of the absolute public constant fixture with `sasrun ... -f text -o - -l /dev/null`
reproduced its 15-row expected file byte-for-byte; output is retained locally at
`/tmp/opensas-dev3-recovery-20261114-constant.txt`.

Eight focused Zig tests pass, including the shared-period regression against
dev4's independently retained M9 density at -.5. This preserves the distinction
between the finite Fourier numerical formula and oracle parity: 10,082 kernel
density rows match, three remain recorded disagreements. No density tolerance
was relaxed. The full gate result and exact tested commit are supplied in the
final handoff; focused tests alone do not establish public adapter completion.

The first full gate exposed a listing-only leading blank line in the constant
golden (2,056/2,057 corpus cases, 11/11 programs). The fresh SAS stdout starts
with one blank line; removing exactly that byte gives byte-for-byte equality
with all 15 interpreter rows. The corpus golden removes only that listing
preamble. No numeric text, row, tolerance or interpreter behavior was changed.
The original SAS log and fresh stdout remain intact as evidence.
