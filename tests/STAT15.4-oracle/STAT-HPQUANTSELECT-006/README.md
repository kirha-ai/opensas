# STAT-HPQUANTSELECT-006 — HPQUANTSELECT — Macro Variables That Contain Selected Effects / Using the Validation ACL as the STOP= Criterion / Using the Validation ACL as the CHOOSE= Criterion

## Source

S154 / Chapter 66 / `Macro Variables That Contain Selected Effects` (PDF pp. 5003–5005); S154 / Chapter 66 / `Using the Validation ACL as the STOP= Criterion` (PDF p. 5006); S154 / Chapter 66 / `Using the Validation ACL as the CHOOSE= Criterion` (PDF p. 5006).

## Scope

Implement Macro Variables That Contain Selected Effects; Using the Validation ACL as the STOP= Criterion; Using the Validation ACL as the CHOOSE= Criterion. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Macro Variables That Contain Selected Effects / Using the Validation ACL as the STOP= Criterion / Using the Validation ACL as the CHOOSE= Criterion, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Seeded synthetic quantile-regression fixture: Macro Variables That Contain Selected Effects / Using the Validation ACL as the STOP= Criterion / Using the Validation ACL as the CHOOSE= Criterion |

**documented_feature:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
