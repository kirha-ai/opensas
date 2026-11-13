# FEAT-freq-exact public integration — batch 3

Status: **public integration implemented, not full-ticket acceptance**. Numerical support owns
`freq_exact_unconditional.zig` and `freq_exact_polynomial.zig`; this change does
not edit either file.

## Blaker follow-up after fed5f13 landed

Review correctly identified a public interval gap omitted from the previous
handoff. Blaker is in this ticket's delegated exact-interval scope: the manual
documents BINOMIAL(CL=BLAKER) at pp.110 and 177 and defines it by inversion of
the two-sided exact Blaker test. It is a TABLES interval option, not a separate
EXACT statistic option. The previously retained numerical kernel was not enough
to claim that public path was connected.

The parser and risk execution adapter now dispatch CL=BLAKER to that kernel.
No EXACT statement is required. Fractional frequencies produce SAS's NOTE and
omit the Blaker interval; unsupported oversized counts remain fail-loud.
This follow-up changes no numerical algorithm or expected listing fixture.

Actual runtime evidence is retained here as `blaker.sas`, `blaker.txt`, and
`blaker.log`: SAS_VERSION=9.04.01M9P060525, zero errors and zero warnings.
The k=2,n=10 interval is [.03677145593142,.55555286230792]; k=0 and k=10
limits print [0,.2829] and [.7171,1]. The fractional case k=2.5,n=10 emits
the documented NOTE and no Blaker interval. Public regression exercises these
paths, mixed CL=(BLAKER EXACT), formatted LEVEL selection, and invalid families
or CORRECT suboptions. The full-ticket RR compatibility blocker remains open.

## Actual SAS 9.4 M9 evidence, 2026-11-13

Command: `/Users/thomas/sas/bin/sasrun <absolute-path> -f text -o - -l /dev/null`.
Probe directory: `/private/tmp/opensas-dev3-exact-b3/`.
Numbers below are transcribed from actual SAS stdout, not opensas goldens.

* `public.sas`: 0 errors/warnings. `[1,9;11,3]` Fisher left .0014, right 1,
  single-table probability .0013, two-sided .0028, tied POINT .0027, MIDP .0014.
  MC/N/SEED do not change 2x2 Fisher to simulation. PCHI MC N=10000 SEED=17:
  .0026, 99% CI [.0013,.0039].
* `families.sas`: final run with ODS GRAPHICS OFF: 0 errors/warnings. The first
  run had two image-permission errors and is not accepted as a clean run.
  `[3,0,1;0,2,1;1,0,2]`: PCHI .1010, LRCHI .2229, MHCHI .3295;
  PCORR one/two .1648/.3295, SCORR .1267/.2533;
  KENTB/STUTC/SMDCR/SMDRC/JT .0905/.1810; KAPPA .0267/.0267,
  WTKAPPA .0905/.1200; SYMMETRY 1, POINT .5.
  Two `[2,0;0,2]` strata: COMOR lower 1.3633, upper infinity, one-sided .0278,
  POINT .0278, MIDP .0139, all three two-sided definitions .0556; Zelen omitted.
  Binomial k=2,n=10,p0=.3: CP [.0252,.5561], p1 .3828, p2 .7656,
  POINT .2335, MIDP .2660. Multinomial same counts/expected probabilities:
  PCHI p .7332, POINT .4336, MIDP .5164; LRCHI p .5331, POINT .2335, MIDP .4163.
* `bin-controls.sas`: 0 errors/warnings. k=2,n=10,p0=.3,margin=.1:
  exact NI .6242, superiority .9536; equivalence lower .6242, upper .1673,
  overall .6242. Exact 90% limits [.0368,.5069]. These do not replace equality.
* `sparse.sas`: 0 errors/warnings. `[0,0;1,2]` with ZEROS: only agreement
  statistics survive; McNemar and Kappa exact p-values are 1.
  `[0,2;3,0]`, ALPHA=.95, RR NOSCORE upper .3104.
* `intervals.sas`: 0 errors/warnings. `[1,3;3,1]`: OR [.0016,4.7229];
  RD SCORE2 column 1 [-.9072,.2500], column 2 [-.2500,.9072]; RR SCORE2
  column 1 [.0238,1.6859], column 2 [.5932,42.0397]. BARNARD one/two
  .144531/.289063. PFORMAT=8.6 Fisher p .485714, POINT .457143, MIDP .257143.
* `cl-controls.sas`: 0 errors, 5 expected semantic warnings. CL=EXACT without
  an EXACT statement warns and does not compute the requested exact limit.
  TABLES COLUMN=2 does not override EXACT defaults (RD BOTH, RR 1); the RR
  column-2 CL request warns when EXACT only selects column 1.
* `cl-regression.sas`: 0 errors/warnings. Existing formerly unsupported
  corpus fixture `[12,8;5,25]`, riskdiff(cl=exact), exact riskdiff:
  column 1 [.1145,.6675], column 2 [-.6675,-.1145].
* `inapplicable.sas`: 0 errors/warnings. Two 3x3 strata with all unit counts:
  COMOR/EQOR are not applicable and do not produce an error; implied CMH
  statistics are still displayed.
* `rr-score2-precision.sas`: 0 errors/warnings. ODS RelativeRiskCLs,
  BEST32, `[1,3;3,1]`, column 2, SCORE2, alpha .05:
  lower .59316071031463, upper 42.0396959567221. The public discrepancy
  is not an inference from a rounded listing.
* `high-alpha.sas`: 0 errors/warnings. k=2,n=10,p0=.3, NI margin .1,
  TABLES ALPHA=.6: exact p .6242, exact nominal -20% limits [.1921,.2255].
  Public regression retains the risk ticket's landed high-alpha behavior.

Retained counterexample tests and evidence comments in
`freq_exact_unconditional.zig` were inspected before changes. Original
`/tmp/opensas-stat-batch2/FEAT-freq-exact` and `EXACT-RR-support` probe directories
were absent; no claim is made to have reread missing files.

## Runnable checks

Nine public acceptance tests in `freq_exact_public.zig`: Fisher ties and MC fallback;
MC reproducibility/deadline; conditional families and TABLES selection;
binomial/multinomial/NI/superiority/TOST; zero margins and captured fractional
count errors; stratified conditioning and missing controls; interval family
methods/column orientation and PFORMAT; CL=EXACT prerequisites and column
defaults; and the Blaker follow-up described above. A separate public test retains the ordinary-alpha RR SCORE2
endpoint discrepancy as a mathematical reciprocal/known-difference certificate;
it is explicitly NOT a SAS acceptance pass. Existing enumeration,
six-standard-error Monte Carlo checks, and confidence boundary tests remain.
The obsolete Fisher rejection assertion in `proc.zig` is replaced by affirmative
public tests. The earlier CL=EXACT gap fixture was converted to a supported
listing in a separate oracle-backed commit; the Blaker follow-up adds no golden.

## Remaining acceptance work

* Retained RR NOSCORE/SCORE/SCORE2 sparse high-alpha discrepancies remain in
  scope. Fresh .3104 evidence reproduces one of them. Public execution calls
  `riskLimitsSas`; this is not a claim that its current profile achieves full
  SAS parity. No tolerance was widened.
* TABLES risk CL=EXACT integration is now implemented with manager authorization
  for the two minimal risk parser/executor changes. The ordinary-alpha RR
  SCORE2 column-2 case `[1,3;3,1]` currently differs as well: kernel 42.0395,
  SAS 42.0397. Per the manager's instruction to finish public integration while
  retaining the same-ticket numerical blocker, this case is a known-difference
  certificate, not a falsely passing SAS assertion. No tolerance was widened,
  and it remains part of the incomplete acceptance inventory.
* The single final rebase onto local `feat/stat/batch-3` at
  `0f2d151e755c382d1fbc4330344808b3be2508bf` completed without conflicts;
  the ODS capture hook and landed risk changes were preserved. Final gate
  counts and green SHA are reported in the manager handoff.
  Parser acceptance or a green gate alone does not complete this ticket.
