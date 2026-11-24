# STAT-TTEST-009 — TTEST — TOST Equivalence Test

## Source

S154 / Chapter 128 / `TOST Equivalence Test` (PDF pp. 10630–10631).

## Scope

Implement TOST Equivalence Test. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For TOST Equivalence Test, separately verify both one-sided tests, the combined equivalence decision, and the corresponding interval confidence level; cover exact equivalence boundaries and difference/ratio scales; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [tost_difference.sas](tost_difference.sas) | captured | 0 | [listing](tost_difference.expected.txt) / [log](tost_difference.oracle.log) | Both one-sided equivalence tests, combined decision and 90% equivalence interval |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
