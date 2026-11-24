# STAT-PRINQUAL-004 — PRINQUAL — Splines / Controlling the Number of Iterations / Performing a Principal Component Analysis of Transformed Data

## Source

S154 / Chapter 99 / `Splines` (PDF pp. 8062–8063); S154 / Chapter 99 / `Controlling the Number of Iterations` (PDF pp. 8063–8064); S154 / Chapter 99 / `Performing a Principal Component Analysis of Transformed Data` (PDF p. 8064).

## Scope

Implement Splines; Controlling the Number of Iterations; Performing a Principal Component Analysis of Transformed Data. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Splines / Controlling the Number of Iterations / Performing a Principal Component Analysis of Transformed Data, verify basis/kernel definitions, knots or bandwidths, boundaries, and predictions against an independent grid calculation and the source examples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 99.2: Principal Components of Basketball Rankings |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Restored the ten ranking fields with underscore-separated school labels and list input; published missing ranks remain missing.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
