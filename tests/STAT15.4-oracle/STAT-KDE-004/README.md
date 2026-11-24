# STAT-KDE-004 — KDE — Kernel Density Estimates / Binning / Kernel Distribution Estimates

## Source

S154 / Chapter 73 / `Kernel Density Estimates` (PDF pp. 5406–5407); S154 / Chapter 73 / `Binning` (PDF pp. 5407–5409); S154 / Chapter 73 / `Kernel Distribution Estimates` (PDF pp. 5409–5411).

## Scope

Implement Kernel Density Estimates; Binning; Kernel Distribution Estimates. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Kernel Density Estimates / Binning / Kernel Distribution Estimates, verify basis/kernel definitions, knots or bandwidths, boundaries, and predictions against an independent grid calculation and the source examples; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 73.5: Univariate KDE Graphics |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
