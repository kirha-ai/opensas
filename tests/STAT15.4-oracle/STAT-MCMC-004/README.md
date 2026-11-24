# STAT-MCMC-004 — MCMC — ARRAY / BEGINCNST/ENDCNST / BEGINNODATA/ENDNODATA Statements

## Source

S154 / Chapter 80 / `ARRAY Statement` (PDF p. 6117); S154 / Chapter 80 / `BEGINCNST/ENDCNST Statement` (PDF pp. 6117–6119); S154 / Chapter 80 / `BEGINNODATA/ENDNODATA Statements` (PDF p. 6119).

## Scope

Implement ARRAY; BEGINCNST/ENDCNST; BEGINNODATA/ENDNODATA Statements. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For ARRAY / BEGINCNST/ENDCNST / BEGINNODATA/ENDNODATA Statements, verify target log densities, parameter support, and the relevant sampling/summary steps; check fixed-seed reproducibility and posterior moments/intervals against known analytic distributions; record chain diagnostics and Monte Carlo error.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 80.4: Logistic Regression Model with Jeffreys' Prior; explicit statements: ARRAY |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: ARRAY. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
