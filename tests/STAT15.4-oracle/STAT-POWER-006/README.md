# STAT-POWER-006 — POWER — PAIREDMEANS / TWOSAMPLEFREQ / TWOSAMPLEMEANS

## Source

S154 / Chapter 96 / `PAIREDMEANS Statement` (PDF pp. 7799–7808); S154 / Chapter 96 / `TWOSAMPLEFREQ Statement` (PDF pp. 7813–7820); S154 / Chapter 96 / `TWOSAMPLEMEANS Statement` (PDF pp. 7820–7830).

## Scope

Implement PAIREDMEANS; TWOSAMPLEFREQ; TWOSAMPLEMEANS. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For PAIREDMEANS / TWOSAMPLEFREQ / TWOSAMPLEMEANS, verify paired differences, pairwise missing-value exclusion rules, degrees of freedom, and intervals; reversing pair order must correctly change direction and one-sided probabilities; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: POWER Procedure; explicit statements: TWOSAMPLEMEANS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: TWOSAMPLEMEANS. Remaining statement variants: PAIREDMEANS, TWOSAMPLEFREQ.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
