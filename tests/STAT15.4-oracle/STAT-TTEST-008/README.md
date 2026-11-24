# STAT-TTEST-008 — TTEST — AB/BA Crossover Design

## Source

S154 / Chapter 128 / `AB/BA Crossover Design` (PDF pp. 10629–10630).

## Scope

Implement AB/BA Crossover Design. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For AB/BA Crossover Design, verify sequence, period, treatment contrasts, and the corresponding degrees of freedom; compare each result with the source crossover design example; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [abba_crossover.sas](abba_crossover.sas) | captured | 0 | [listing](abba_crossover.expected.txt) / [log](abba_crossover.oracle.log) | AB/BA treatment and period effects using Example 128.4 input |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
