# GAP-univ-summary-complete — completed acceptance and oracle evidence

Status: complete. The OUTTABLE normality prerequisite is integrated and its
temporary guard is removed. Original development base was
bdfcd4f56fec199f65a859a5fccbd88eb58ca3ea; final integration includes normality
support from fb25b9d75caac2114b351faa723b8fc4c59caeb1.

Reference: SAS 9.4 Statistical Procedures printed pp.299–306, 320–322, 342,
353–358, 408–414, 419–420, 444–447, 460–466. The extracted manual was absent
from the supplied worktree; opensas-private/docs/sas94-procedures-statistical.txt
was read as reference only.

New parsing, computation, output construction and optional-table rendering are
separate functions in `src/stat/univariate.zig`. Existing dispatch and numerical /
grouping helpers are reused through narrow UNIVARIATE changes in `src/proc.zig`.
`src/stat/normality.zig` supplies the independently validated normality kernel.
No manager-tree edits, jira edits, fetch, pull or push were performed.

## Completed surface inventory

| Surface | Accepted behavior and evidence |
| --- | --- |
| OUTPUT name lists | Names map positionally to each VAR; multiple OUTPUT statements create distinct datasets; per-statement dataset options stay local. Manager PCTLDEF4 probe returns 15,250,2.5,125. |
| OUTPUT metadata | SAS canonical statistic order and labels, copied BY/CLASS/ID attributes, no _TYPE_/_FREQ_, exact dataset labels. Name collisions warn and preserve the first value/label. |
| PCTLDEF 1–5 | Shared percentile kernel for fixed/arbitrary OUTPUT and listing. [0,10,20,30] P25=0,0,0,2.5,5. All five definitions verified on 5,003 observations. WEIGHT uses definition 5 independently of PCTLDEF. |
| Percentile syntax/names | Decimal and TO/BY ranges, multiple prefixes, suffix fallback, 32-byte prefix truncation, BYSTAT default / BYVAR order. Omitted PCTLNDEC truncates to two decimals; explicitly specified PCTLNDEC rounds, accepting higher values but capping precision at eight. Labels use the generic percentile request path; no probe-specific production branches remain. |
| Summary keywords | NOBS, Q2, GEOMEAN, HARMEAN; fixed summary keywords; VARDEF=N skewness/kurtosis; singleton MODE. Zero-weight values do not poison geometric/harmonic means. |
| BY/FREQ | Original boundaries recorded after input filtering and before FREQ exclusion. NOTSORTED groups cannot merge when an intervening group is excluded by zero, negative, missing, or fractional-to-zero FREQ. Sorted BY validation also examines those source rows. |
| CLASS | One/two variables; per-variable MISSING and ORDER=DATA/FORMATTED/FREQ/INTERNAL; formatted levels; explicit CLASS-as-VAR preserves numeric analysis data. Raw representatives are the first included value per level and BY group, shared across crossed levels. INTERNAL ordering uses those representatives. |
| Default VAR selection | Excludes BY/CLASS/FREQ/WEIGHT/ID roles; ID prefixes expand before exclusion. Unknown grouping names and nonnumeric analysis/FREQ/WEIGHT variables error. |
| ID/IDOUT/extremes | Source observation identities survive WHERE, grouping and FREQ. IDOUT uses the first source observation of the BY group, even with FREQ=0. NEXTROBS=0 suppresses the table; NEXTRVAL uses unique values. FREQ does not duplicate physical extreme observations. |
| Modes/frequency display | All tied modes, counts, weighted counts and percentages; singleton MODE is its value; unique multi-observation samples have missing MODE. PROC FREQ display option remains distinct from the FREQ statement. |
| ROUND | Even-multiple ties, negative halves and decimal units, per-VAR units, original ID labels. A separate analysis view preserves original BY/CLASS keys and original WEIGHT values when the same column serves both roles. |
| Weighted/empty cases | Missing/nonpositive weights and EXCLNPWGT aliases; truncated FREQ; correct counts. All-zero weights give midpoint(min,max) percentiles and CSS=0. Empty OUTPUT retains its schema. Empty physical input yields an undescribed OUTTABLE; nonempty input excluded from analysis retains its descriptor. |
| OUTTABLE schema/order | _VAR_, _VARI_, _NOBS_ as nonmissing count; optional _LABEL_ only for labeled analysis variables, fixed length 40; _VAR_ grows from minimum 8 to the longest analysis name. Rows are BY-major, then VAR-major, then CLASS. |
| OUTTABLE computations | Baseline moments, quantiles, location tests, robust scales, geometric/harmonic means and normality fields are populated. No fabricated missing normality fields. Weighted samples bypass unsupported normality/robust calculations as SAS does. |
| Normality integration | Sorted nonmissing FREQ-expanded samples passed to compute(). Null means both fields missing. Distinct n=2 gives W=1,p=1; constants/singletons are missing; W through n=2000, fitted-normal D above 2000; stored KS p bounded at .01/.15. |
| Large samples | 5,003 observations for every PCTLDEF; four grouped analyses each with 5,003 physical / 7,505 FREQ-expanded observations; two VARs, two CLASS variables, BY, IDOUT, FREQ/WEIGHT and complete metadata. All emitted value/metadata tokens match SAS. |

Optional full NORMAL/CIBASIC/robust-inference statement/output requests belong
to the separate inference scope and remain explicit gaps. The required baseline
OUTTABLE fields are implemented regardless of those optional requests.

## Normality numerical qualification

The support evidence is [univ-normality.md](../univ-normality.md). Its documented
algorithm and empirical near-constant qualification apply unchanged here.
SAS makes normality missing near a relative population-variance threshold of
500 machine epsilons. At the exact floating-point cutoff, SAS accumulation order
can change missing/nonmissing classification. The helper uses stable moments;
last-bit boundary classification is not claimed bit-identical. Unambiguous .99
and 1.01 sides are tested at n=2/8/12/2000/2001. This is an explicitly recorded
numerical boundary qualification, not an unimplemented method or fallback.

The integration fixture checks n=1/2/3/8/11/12/2000/2001/5003, constants,
FREQ-expanded n=2000/2001, crossed BY/CLASS groups with two differently shaped
analysis variables, weighted bypass and empty input. Normality values at
8 decimals and robust scales at 6 decimals match the SAS oracle exactly.

## Retained synthetic oracle families

Each family has `.sas`, raw `.txt` and complete `.log` files (an error-only probe
can have no result file). Invocation:

    /Users/thomas/sas/bin/sasrun INPUT -f text -o OUTPUT -l LOG

- `dev3-univ-probe`, `dev3-meta`: summary/OUTTABLE descriptors, canonical keyword
  order and labels, rounding, modes/extremes, weighted/FREQ cases.
- `dev3-edge`, `dev3-edges`: grouping, physical IDs after WHERE/FREQ, weighted
  OUTTABLE, empty OUTPUT and per-variable decimal rounding.
- `dev3-zero`, `dev3-zero2`: zero-total-weight midpoint fallback and singleton MODE.
- `dev3-idout`, `dev3-defaults`: excluded first-source IDOUT, ID default exclusion,
  exact Weighted percentile-definition dataset label.
- `dev3-name-explicit`, `dev3-ndec`, `dev3-ndec-range`, `dev3-pctlnames`,
  `dev3-collision`: omitted-versus-explicit decimal naming, precision cap, decimal
  padding and first-value retention on name collisions.
- `dev3-roundid`, `dev3-roundroles`: original ID labels and independent
  BY/CLASS/WEIGHT roles under ROUND.
- `dev3-robust`, `dev3-summary`: small-sample robust values, zero weights,
  multiple outputs, VARDEF=N and scalar means.
- `dev3-large`, `dev3-multigroup`: >4096 sample acceptance and combined descriptor
  checks; comparisons ignore SAS page wrapping, not values or metadata tokens.
- `dev3-classrep`, `dev3-classcross`, `dev3-classvar`: first raw representatives,
  FREQ exclusions, cross-level sharing, per-BY reset, CLASS-as-VAR.
- `dev3-emptytable`, `dev3-tablemeta`: zero-row descriptors and label/name lengths.
- `dev3-outtable-final`: complete end-to-end OUTTABLE normality and robust fields.
- `dev3-byfreq-final`, `dev3-byfreq-unsorted`: all excluded FREQ boundary cases,
  source-based sorted-BY error, and ID-prefix default selection.
- `invalid-pctl`: real SAS rejects PCTLPTS without PCTLPRE; OpenSAS exit 1.

Two existing metadata-reader differences are outside UNIVARIATE: ATTRC currently
implements MEMNAME only, and PROC CONTENTS OUT= row order differs from SAS unless
explicitly sorted. Dataset labels are therefore checked directly in unit tests
and through CONTENTS listings; metadata comparisons explicitly sort by VARNUM.
The stored UNIVARIATE descriptor itself is verified, without changing these readers.

## Regression fixtures and golden provenance

`univ_summary_complete`, `univ_summary_edges`, `univ_summary_large`,
`univ_summary_multigroup`, `univ_summary_classmeta`, `univ_outtable_normality`,
`univ_summary_boundaries`, and `univ_round_roles` are runnable synthetic fixtures.
Unit tests additionally assert descriptors, malformed requests and algorithmic
selection against exhaustive pair distances. Test rejection paths use captured
diagnostics. Robust selection uses bounded scratch space. The documented default Qn cutoff
above 65,526 observations is pinned by the `dev3-outtable-qnlimit` oracle and a
65,527-value unit test; Sn remains populated there. The documented default Sn
cutoff above one million observations is also honored.

Expected-output commits are separate from implementation, with oracle families
and applicable manual pages in their messages. Existing golden changes reflect
canonical OUTPUT order/labels, ascending high extremes and tie/source identity,
VARDEF=N moments, singleton MODE and replacement of obsolete feature guards.
New golden value/metadata tokens were compared to real SAS before recording.

## Trackers

No scalar function is introduced, so sas-functions.md is unchanged.
sas9.4.ebnf explicitly excludes UNIVARIATE and the other statistical procedures;
no unsupported whole-PROC marker is added. This completed inventory records the
summary grammar, supported output contract, and numerical qualification.
