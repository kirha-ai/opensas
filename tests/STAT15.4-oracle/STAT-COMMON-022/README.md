# STAT-COMMON-022 — EFFECT — Multimember Effects / Polynomial Effects

## Source

S154 / Chapter 20 / `Multimember Effects` (PDF pp. 429–431); S154 / Chapter 20 / `Polynomial Effects` (PDF pp. 431–434).

## Scope

Implement shared semantics, defaults, and applicability checks for multimember Effects; Polynomial Effects; procedure-specific options and result integration belong to the corresponding PROC tickets.

## Acceptance criteria

Create positive and negative cases for the syntax forms, defaults, and option combinations listed in this section; verify result names, dimensions, and numerical values.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [polynomial_effect.sas](polynomial_effect.sas) | captured | 0 | [listing](polynomial_effect.expected.txt) / [log](polynomial_effect.oracle.log) | Polynomial effect construction through second degree |

**polynomial_effect:** Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
