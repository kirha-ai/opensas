# STAT-FREQ-007 — complete binomial proportion reporting

Starting base: 0226cdbccf9314ebe8537e02f9ae72a253e6aa41; branch codex/stat-dev3.
Read the full ticket, own README, every listed case/expected/status/log (one case), and manual
physical pages 3180–3188. Original oracle files are unchanged. Main/proc/global code was not
edited. Final SHA/base and direct-exit gate counts are reported in the handoff.

## Concrete baseline gaps and changes

The original case returned 0 with correct numerical results but failed complete text comparison
(269 actual tokens versus 257 expected). Generic risk tables did not show the requested binomial
field structure, confidence captions, null-SE labels, equivalence hypotheses/margins or TOST
layout. One equivalence limit printed a binary floating-point artifact. The procedure heading
was repeated before the second binomial panel and the frequency rules had the wrong width.

A typed binomial listing view now consumes the existing estimate, interval and inference results.
Generic sections remain available to existing capture consumers; no mathematical kernel is
reimplemented or changed. Explicit CI methods are listed under their confidence heading; default
Wald and Clopper-Pearson limits are displayed in the proportion block. Equality tests identify
the null SE, and sample-variance equivalence shows both hypotheses, signed margins, both TOST
components, overall p-value and equivalence/CI endpoints. Established NI/SUP/null-variance
sections remain available through their existing rendering path. Layout changes are restricted
to binomial panels; ordinary frequency reports retain their established layout.

The new corpus fixture includes the unchanged oracle source and pins every displayed field,
method, both TABLES requests and their ordering. Existing captured parser checks now explicitly
cover P=100 as well as P=0 rejection; existing P=1 coverage confirms the documented 1% meaning.
All-zero/all-success and interval-method unit coverage is reused. Eight binomial goldens and the
new full-example golden are committed separately, with the oracle evidence in the message.

## Reproducible complete comparison

```sh
python3 tests/STAT15.4-oracle/STAT-FREQ-007/verify.py --output /absolute/fresh/output-directory
```

The replay preserves full actual stdout/stderr/status, generated positive boundary programs,
and a compact manifest. dev3-verification.json records input/output hashes and independent
unrounded references. Only whitespace runs/edges are normalized. No headers, fields, tables,
limits, probabilities or diagnostics are dropped; no blanket numerical tolerance is used.
The original case matches all 257 tokens with status 0 and empty stderr, matching expected
warning/error semantics. SAS informational source/read/page notes differ; no exemption is
claimed. Graphics are disabled and none are produced.

## Independent numerical checks

Both analyses have N=762. Eyes selects brown, x=341; Hair selects fair, x=228. The verifier
computes p=x/n, sample ASE, null-based equality SE, normal test statistics and one-/two-sided
tails independently. Wald, Agresti-Coull and Wilson limits follow the cited formulas. Exact
Clopper-Pearson endpoints are found by inverting directly summed binomial probabilities using
50-digit Decimal arithmetic, not OpenSAS beta/F routines. Comparisons use the exact four-decimal
and PVALUE display conventions and retain unrounded references.

Eyes: p=0.4475, ASE=0.0180, 90% AC/Wilson limits [0.4181,0.4773], exact limits
[0.4174,0.4779]; null p0=.5 gives SE=0.0181, Z=-2.8981, tails .0019/.0038.
Hair: p=0.2992, ASE=0.0166, 95% Wald limits [0.2667,0.3317], exact [0.2669,0.3331];
null p0=.28 gives SE=0.0163, Z=1.1812, tails .1188/.2375. Equivalence limits .18/.38
produce Z=7.1865 and -4.8701; both one-sided p-values and their maximum are <.0001.
The 90% equivalence confidence interval is [0.2719,0.3265].

Five independently calculated positive probes cover x=0/n=10, x=10/n=10, x=2/n=10,
and near-boundary nulls .99 and .01. WEIGHT/ZEROS retains the absent event level. All return
0 with empty stderr; every requested AC/exact/Wald/Wilson interval, proportion, ASE and equality
test matches at its printed precision. Existing captured diagnostics cover invalid endpoint nulls
and invalid noninferiority/equivalence limits without spawning aborting test processes.
