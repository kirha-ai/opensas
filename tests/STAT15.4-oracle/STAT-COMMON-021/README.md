# STAT-COMMON-021 — EFFECT — Collection Effects / Lag Effects

## Source

S154 / Chapter 20 / `Collection Effects` (PDF p. 426); S154 / Chapter 20 / `Lag Effects` (PDF pp. 426–429).

## Scope

Implement shared semantics, defaults, and applicability checks for collection Effects; Lag Effects; procedure-specific options and result integration belong to the corresponding PROC tickets.

## Acceptance criteria

Create positive and negative cases for the syntax forms, defaults, and option combinations listed in this section; verify result names, dimensions, and numerical values.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [collection_effect.sas](collection_effect.sas) | captured | 0 | [listing](collection_effect.expected.txt) / [log](collection_effect.oracle.log) | Collection effect expansion and selected model columns |

**collection_effect:** Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
