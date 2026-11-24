# STAT-TTEST-011 — TTEST — ODS Graphics

## Source

S154 / Chapter 128 / `ODS Graphics` (PDF pp. 10644–10650).

## Scope

Implement ODS Graphics. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For ODS Graphics, verify graph names, triggering conditions, curve/point data, axes, grouping, and legends; check the relevant PLOTS= and ODS GRAPHICS controls and visually inspect exported graphs.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [graph_names.sas](graph_names.sas) | captured | 0 | [listing](graph_names.expected.txt) / [log](graph_names.oracle.log) | Interval and QQ graph creation and ODS TRACE names; text listing is paired with the graph trace |

**graph_names:** The listing and log capture graph requests and ODS names; a visual artifact capture is still required for complete graphics coverage.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
