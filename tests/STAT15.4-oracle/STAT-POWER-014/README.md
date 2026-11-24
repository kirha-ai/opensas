# STAT-POWER-014 — POWER — Analyses in the PAIREDMEANS / Analyses in the TWOSAMPLEFREQ / Analyses in the TWOSAMPLEMEANS

## Source

S154 / Chapter 96 / `Analyses in the PAIREDMEANS Statement` (PDF pp. 7895–7900); S154 / Chapter 96 / `Analyses in the TWOSAMPLEFREQ Statement` (PDF pp. 7900–7905); S154 / Chapter 96 / `Analyses in the TWOSAMPLEMEANS Statement` (PDF pp. 7905–7912).

## Scope

Implement Analyses in the PAIREDMEANS; Analyses in the TWOSAMPLEFREQ; Analyses in the TWOSAMPLEMEANS. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Analyses in the PAIREDMEANS / Analyses in the TWOSAMPLEFREQ / Analyses in the TWOSAMPLEMEANS, verify paired differences, pairwise missing-value exclusion rules, degrees of freedom, and intervals; reversing pair order must correctly change direction and one-sided probabilities; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 96.2: The Sawtooth Power Function in Proportion Analyses |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
