# STAT-GENMOD-010 — GENMOD — EXACT / EXACTOPTIONS / Exact Logistic and Exact Poisson Regression

## Source

S154 / Chapter 51 / `EXACT Statement` (PDF pp. 3535–3538); S154 / Chapter 51 / `EXACTOPTIONS Statement` (PDF pp. 3538–3541); S154 / Chapter 51 / `Exact Logistic and Exact Poisson Regression` (PDF pp. 3612–3615).

## Scope

Implement EXACT; EXACTOPTIONS; Exact Logistic and Exact Poisson Regression. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For EXACT / EXACTOPTIONS / Exact Logistic and Exact Poisson Regression, independently enumerate probability masses and the relevant tails/intervals for small samples; cover ties, zero counts, degenerate boundaries, and exact-method applicability restrictions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 51.11: Exact Poisson Regression; explicit statements: EXACT, EXACTOPTIONS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: EXACT, EXACTOPTIONS. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
