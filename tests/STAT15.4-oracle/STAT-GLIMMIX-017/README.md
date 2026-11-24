# STAT-GLIMMIX-017 — GLIMMIX — Between-Within Degrees of Freedom Approximation / Containment Degrees of Freedom Approximation / Satterthwaite Degrees of Freedom Approximation / Kenward-Roger Degrees of Freedom Approximation

## Source

S154 / Chapter 52 / `Between-Within Degrees of Freedom Approximation` (PDF p. 3855); S154 / Chapter 52 / `Containment Degrees of Freedom Approximation` (PDF p. 3855); S154 / Chapter 52 / `Satterthwaite Degrees of Freedom Approximation` (PDF pp. 3855–3857); S154 / Chapter 52 / `Kenward-Roger Degrees of Freedom Approximation` (PDF pp. 3857–3858).

## Scope

Implement Between-Within Degrees of Freedom Approximation; Containment Degrees of Freedom Approximation; Satterthwaite Degrees of Freedom Approximation; Kenward-Roger Degrees of Freedom Approximation. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Between-Within Degrees of Freedom Approximation / Containment Degrees of Freedom Approximation / Satterthwaite Degrees of Freedom Approximation / Kenward-Roger Degrees of Freedom Approximation, independently verify degrees of freedom and their effects on standard errors, tests, and intervals; cover unbalanced designs and boundary variance estimates; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: GLIMMIX Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
