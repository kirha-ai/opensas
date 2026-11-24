# STAT-GENMOD-006 — GENMOD — Zero-Inflated Models / Tweedie Distribution for Generalized Linear Models

## Source

S154 / Chapter 51 / `Zero-Inflated Models` (PDF pp. 3588–3589); S154 / Chapter 51 / `Tweedie Distribution for Generalized Linear Models` (PDF pp. 3589–3591).

## Scope

Implement Zero-Inflated Models; Tweedie Distribution for Generalized Linear Models. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Zero-Inflated Models / Tweedie Distribution for Generalized Linear Models, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 51.12: Tweedie Regression |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
