# STAT-FREQ-007 — FREQ — Binomial Proportion

## Source

S154 / Chapter 47 / `Binomial Proportion` (PDF pp. 3180–3188).

## Scope

Implement Binomial Proportion. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Binomial Proportion, verify each requested proportion estimate, test, and interval method; include all-zero and all-success samples, small samples, and boundary null hypotheses; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 47.4: Binomial Proportions |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
