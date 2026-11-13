# Normal-kernel periodicity handoff

Dev4 changed only its owned `univ_kernel.zig` and statement glue; dev3's bins
and kernel-output helper files are untouched.

`Request.fft_period: ?f64 = null` is an internal, additive hint, not a SAS option.
`Estimate.fftPeriod(range) -> ?f64` supplies the intrinsic period: 2*range or
4*range, with padding capped at four data ranges. Normal cutoff is 3*h;
quadratic/triangular cutoff is h. Multiple bandwidths in one statement share
the largest period; statement glue computes that period per nondegenerate
sample and passes it through the request. Zero range/IQR is left to the
output helper's fallback API rather than rejected by the new precomputation.

`binnedDensity` now uses the wrapped normal kernel, not an unwrapped Gaussian.
It evaluates Gaussian images for narrow bandwidths and the equivalent Fourier
series for broad bandwidths. Reflections outside the native FFT grid contribute
zero. Physical `density` remains the direct unbounded/reflected formula.

Independent M9 probes `dev4-kernel-periodic-single-20261113` and
`dev4-kernel-periodic-heldout-20261113` use x=(0,.3,.8,1), C=.2,.5,1,2. Eight
individual-curve coordinates and the discriminating shared-grid coordinate
agree to 1e-12. C=1/2 produce SAS's expected large-bandwidth wrap warnings.
At C=.2 and x=-.5, density is .00011050570727 in its own statement, but
.0000552502448 when sharing the four-range grid with larger bandwidths.

The output-options fixture also discriminates this correction: class x=(6,8),
C=.5, density at 4 is .01637919; unwrapped convolution gives .01637323.

Remaining output-grid issue for dev3: in `dev4-output-options-20261113`, the
class x=(6,8) has no SAS OUTKERNEL row at value 2, whereas the old output helper
emits it. The option-ordering regression selects value 4, inside every class's
available lattice, and does not waive that separate grid-extent difference.
Constant/comparative and mixed-kernel grid extent acceptance remains with the
assigned helper work; this density change does not claim those complete.
