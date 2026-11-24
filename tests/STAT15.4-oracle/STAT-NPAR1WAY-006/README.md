# STAT-NPAR1WAY-006 — NPAR1WAY — EXACT / Ratio Mean Deviations (RMD) Exact Test / Exact Tests

## Source

S154 / Chapter 90 / `EXACT Statement` (PDF pp. 7225–7229); S154 / Chapter 90 / `Ratio Mean Deviations (RMD) Exact Test` (PDF pp. 7246–7247); S154 / Chapter 90 / `Exact Tests` (PDF pp. 7249–7253).

## Scope

Implement EXACT; Ratio Mean Deviations (RMD) Exact Test; Exact Tests. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For EXACT / Ratio Mean Deviations (RMD) Exact Test / Exact Tests, independently enumerate probability masses and the relevant tails/intervals for small samples; cover ties, zero counts, degenerate boundaries, and exact-method applicability restrictions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 90.5: Exact Savage Multisample Test; explicit statements: EXACT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: EXACT. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
