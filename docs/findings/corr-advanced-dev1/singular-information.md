# Tight polychoric singular-information investigation

Status: evidence supports a generic zero-variance convention, but does not yet
identify PROC CORR's complete singular-boundary iteration. The production guard
is retained. No eigenvalue epsilon was fitted to force the reported correlation.

Sources and stdout pairs are in the `singular-information/` subdirectory.

## What the actual SAS 9.4 M9 probes establish

All source files use invented count tables. Reproduce with the same command shape:

    /Users/thomas/sas/bin/sasrun /absolute/dev1-probe.sas -f text -o - -l /dev/null

`singular-map.sas/txt` varies SINGULAR, iteration limits, transposition, frequency
scale and an independent staircase table. `singular-step.sas/txt` locates the
first successful iteration. Exhausted MAXITER runs intentionally emit warnings.
Both runs have zero errors. `singular-transition.sas/txt` has zero errors/warnings.

- SINGULAR=0, 1e-16, 1e-12, 1e-8, .01 and .5 give identical results, at both
  CONVERGE=.0001 and .00001. This option cannot be used as the polychoric
  inverse's singularity tolerance.
- Original counts [10,4,0;0,8,2;0,0,7]: CONVERGE=1e-5 fails through MAXITER=22
  and succeeds at 23, with rho=.99985326007584, SE=0, Wald missing,
  LR=40.9081058800832.
- Transpose: same first success at 23, rho=.99985328932097, SE=0.
- Frequencies multiplied by 100: same first success at 23,
  rho=.99985334097333, SE=0, LR=4090.81058800832.
- Held-out counts [5,7,0;0,8,3;0,0,12]: first success at 24,
  rho=.9999, SE=0, Wald missing, LR=41.1053771273106. CONVERGE=1e-6, 1e-8
  and 1e-12 give the same result.
- A convergence sweep is discontinuous: at .000029 the original table has
  rho=.99947448598746 and SE=4.15748848517037; at .000026 it instead reaches
  rho=.99985326007584 and SE=0. This is not a smooth small-SE limit.

## Generic matrix inverse evidence

`ginverse-oracle.sas/txt` feeds independently constructed expected-information
matrices to actual SAS/IML GINV, SWEEP and EIGEN. These are our mathematical
information matrices at marginal thresholds, not matrices extracted from PROC
CORR internals. Both generic inverse operators return zero rho variance for the
nearly singular examples. For rho=.9998 the minimum/maximum eigenvalue ratio is
about 7.37e-17; at rho=.99985326007584 it is about 1.98e-24. At rho=.9997 the
ratio is about 4.93e-10 and both return large finite variance.

`ginverse-rank.sas/txt` separates operator behavior on diagonal matrices of sizes
2, 5 and 10, scaled by 1 or 100:

- GINV's rank decision is scale-relative and depends on dimension: at size 5,
  a relative eigenvalue 1e-13 is inverted but 1e-14 is dropped; at size 10,
  1e-13 is dropped. Scaling the whole matrix by 100 preserves these decisions.
- SWEEP's decision differs. In these diagonal examples an absolute pivot 1e-12
  is retained and 1e-13 is zeroed. Scaling a matrix can therefore change which
  relative eigenvalues SWEEP retains.

These observations distinguish generic inverses and exclude treating them as
interchangeable. They are not a license to pick an epsilon that happens to fit
one CORR result. In particular, the scale invariance of the CORR stopping step
is useful evidence, but does not by itself identify the inverse routine.

SAS documents GINV as the Moore-Penrose inverse computed by SVD, and SWEEP as a
different operator with sequential/reversibility properties. Neither page says
that CORR calls that particular public function:

- https://support.sas.com/documentation/cdl/en/imlug/65547/HTML/default/imlug_langref_sect151.htm
- https://support.sas.com/documentation/cdl/en/imlug/68150/HTML/default/imlug_langref_sect471.htm
- https://blogs.sas.com/content/iml/2015/04/08/rank-of-matrix.html

## Why a zero mapping has not been enabled

`iml-scoring.sas/txt` and `iml-sweep-scoring.sas/txt` reconstruct Fisher scoring
inside actual SAS/IML, using SAS PROBBNRM rectangle differences, analytic cell
derivatives, Pearson initialization, and covariance from the final scoring
linearization. They reproduce the default/loose regime but do NOT reproduce the
tight PROC CORR stopping trajectory:

| Reconstruction | Original table | Held-out table |
|---|---|---|
| GINV | iteration 30, rho=.99964032322852, SE≈2.88e-12 | iteration 30, rho=.99954653571436, SE≈1.85e-12 |
| SWEEP | iteration 30, rho=.99964001285361, SE=0 | iteration 31, rho=.99956023948087, SE=0 |
| Actual PROC CORR | iteration 23, rho=.99985326007584, SE=0 | iteration 24, rho=.9999, SE=0 |

The traces retain raw/relative information eigenvalues and the number of rectangle
probabilities rounded to zero. At original-table iteration 23, the reconstruction
still has eigenvalue ratio about 3.8e-5 and finite SE≈15, whereas PROC CORR has
already completed. Thus changing only the final inverse or zeroing the variance
at a convenient rho would hide a different iteration path.

Both reconstruction runs have zero errors/warnings. Counter-controlled exits are
used because LEAVE in the exploratory IML program did not provide the desired
nested-loop exit behavior. All diagnostic-only initial prints were removed from
the retained successful sources.

The remaining question is the CORR-specific probability/information update and
singular step, not whether a generalized inverse can legitimately return zero.
No unverified rule was added to production. Existing captured diagnostics still
cover this unsupported tight-boundary case; default/loose sparse inference stays
supported. The parent ticket remains DOING.
