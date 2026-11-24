# STAT-LOGISTIC-011 — LOGISTIC — EXACT / EXACTOPTIONS / Exact Conditional Logistic Regression

## Source

S154 / Chapter 79 / `EXACT Statement` (PDF pp. 5861–5863); S154 / Chapter 79 / `EXACTOPTIONS Statement` (PDF pp. 5863–5867); S154 / Chapter 79 / `Exact Conditional Logistic Regression` (PDF pp. 5949–5954).

## Scope

Implement EXACT; EXACTOPTIONS; Exact Conditional Logistic Regression. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For EXACT / EXACTOPTIONS / Exact Conditional Logistic Regression, independently enumerate probability masses and the relevant tails/intervals for small samples; cover ties, zero counts, degenerate boundaries, and exact-method applicability restrictions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 79.11: Conditional Logistic Regression for Matched Pairs Data; explicit statements: EXACT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: EXACT. Remaining statement variants: EXACTOPTIONS.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
