# STAT-POWER-012 — POWER — Analyses in the MULTREG / Analyses in the ONECORR / Analyses in the ONESAMPLEFREQ

## Source

S154 / Chapter 96 / `Analyses in the MULTREG Statement` (PDF pp. 7865–7867); S154 / Chapter 96 / `Analyses in the ONECORR Statement` (PDF pp. 7867–7869); S154 / Chapter 96 / `Analyses in the ONESAMPLEFREQ Statement` (PDF pp. 7869–7887).

## Scope

Implement Analyses in the MULTREG; Analyses in the ONECORR; Analyses in the ONESAMPLEFREQ. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Analyses in the MULTREG / Analyses in the ONECORR / Analyses in the ONESAMPLEFREQ, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 96.2: The Sawtooth Power Function in Proportion Analyses |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
