# STAT-COMMON-023 — EFFECT — Spline Effects / Splines and Spline Bases

## Source

S154 / Chapter 20 / `Spline Effects` (PDF pp. 434–438); S154 / Chapter 20 / `Splines and Spline Bases` (PDF pp. 438–443).

## Scope

Implement shared semantics, defaults, and applicability checks for spline Effects; Splines and Spline Bases; procedure-specific options and result integration belong to the corresponding PROC tickets.

## Acceptance criteria

Create positive and negative cases for the syntax forms, defaults, and option combinations listed in this section; verify result names, dimensions, and numerical values.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [spline_effect.sas](spline_effect.sas) | captured | 0 | [listing](spline_effect.expected.txt) / [log](spline_effect.oracle.log) | Spline effect basis and fitted values |

**spline_effect:** Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
