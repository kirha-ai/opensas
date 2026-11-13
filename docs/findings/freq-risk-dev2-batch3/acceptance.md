# FEAT-freq-risk — batch 3 acceptance

Base: a8de7cc. Scope: risk modules and asymptotic options, pp176–209.

The prior batch already implements binomial Wald/AC/Jeffreys/LR/logit/Wilson,
SENSPEC, risk difference Wald/AC/HA/MN/Newcombe, OR and RR Wald/modified
Wald/score/LR, NI/SUP/equivalence, level and column orientation, and corrections.
The public execution adapter still rejected NI/equivalence ALPHA >= .5 despite
completed numerical kernels. This batch removes that stale wall and avoids
binary floating-point noise in the resulting negative confidence labels.

## Fresh SAS 9.4 M9 oracle

Run each retained source after copying it to a unique absolute dev2 temp path:

    /Users/thomas/sas/bin/sasrun /private/tmp/opensas-dev2-risk-batch3/alpha.sas -f text -o - -l /dev/null
    /Users/thomas/sas/bin/sasrun /private/tmp/opensas-dev2-risk-batch3/boundaries.sas -f text -o - -l /dev/null
    /Users/thomas/sas/bin/sasrun /private/tmp/opensas-dev2-risk-batch3/acceptance.sas -f text -o - -l /dev/null

All three returned 0 errors and 0 warnings. Acceptance concatenates 11 public
fixtures: binomial, twoway, inference, levels, aliases, equality, ni_sup,
correct_direction, boundaries, infinite_fractional, high_alpha.

Fresh discriminating results at ALPHA=.6:

| Analysis | Lower CL | Upper CL | P |
|---|---:|---:|---:|
| Binomial NI, 7/20, null .3 | .3770 | .3230 | .3196 |
| Difference Newcombe NI, [12,8;5,25] | .4666 | .4013 | not a test |
| RR score equivalence, margins [.8,1.25] | missing | missing | .9949 |

SAS labels these -20% intervals. Reversed endpoints are intentional.
Opposite-boundary [10,0;0,10]: MN difference [.6636,1], reversed-column
[-1,-.6636]; RR score [3.4730,infinity], LR [5.7224,infinity]. Reversed
columns give RR score [0,.2879], LR [0,.1748]. Empty column margins suppress
statistics. The new kernel regression pins these printed values at .00005.

## Retained evidence and dependencies

The referenced prior docs/findings risk files and /tmp/opensas-stat-batch2 risk
probes were absent. Prior numerical oracle assertions remain in freq_risk.zig,
freq_risk_inference.zig and freq_risk_execute.zig and were inspected.
The SCORE/SCORE2 boundary certificates remain in freq_exact_unconditional.zig
(tests at lines 635 onward in this baseline). They concern exact-tail inversion;
this batch does not erase, weaken, or claim to resolve them. No exact module,
public EXACT parser, ODS infrastructure, or shared parser change is made.

Nonexact risk methods have no remaining known acceptance gap from this audit.
Full cross-ticket exact acceptance still depends on dev3: CL=EXACT integration,
Blaker and SCORE/SCORE2 runtime discrepancies must not be represented as done
by this risk-module result. BINOMIAL OUTLEVEL remains an explicit unsupported
output-dataset request, outside numerical/listing coverage and needing shared
output integration; it is not silently ignored.

Regression: runnable high-alpha public fixture plus public adapter assertion;
opposite-boundary kernel regression; existing risk suites retained.
