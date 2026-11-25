# dev3 — STAT-FREQ-001 full oracle verification

Both unchanged oracle cases PASS: complete whitespace-normalized listings, expected return
status 0, and no warnings/errors. The earlier partial-attempt conclusion is superseded.
Dev2's shared prelude fix is integrated by rebase; no shared-option fix was duplicated.

Baseline: c2bc2789f9b89415260bb50c8939bebe6f88dca8. Branch: codex/stat-dev3.
The manager already landed the initial heading fix. Final branch/base/SHA and the integration
gate result are reported in the handoff. No oracle source, expected listing, expected status,
or reference log was altered.

## References and scope

Read CLAUDE.md, src/lexer.zig, relevant decisions, this ticket in stat-jira.md and its README.
Read physical PDF pages 3082–3085 and 3157–3162 from
/Users/thomas/kirha/opensas/docs/SAS-STAT-15.4-Users-Guide.pdf (absent in this worktree).
Existing FREQ dispatch, BY, numeric-role and weight filtering APIs are reused.
No MEANS, REG, global dispatch/parser/options, board, or skill edits; no push.

## Concrete corrections

- Preserve variable headings when row names exceed the width of row values. The regression
  covers Internship/Enrollment and a name wider than the entire first cell.
- Show one procedure heading for a multi-stratum table, then a new heading for the summary.
- TABLES NOPRINT no longer emits the suppressed cell table's heading above its statistics.
- Restore the common odds/relative-risk table rule and the vertical Breslow–Day rows/rule.
- Render Simple and Weighted Kappa in one Kappa Statistics table (TABLES=RESTORE preserved).
- Render the full Test of H0 table including Estimate, standard error, Z, and both probabilities.
  Estimate=0.3449 was absent in the original Kappa test table: it was a substantive missing field,
  even though another table displayed the same estimate. The null value now appears in the
  hypothesis heading. Nonzero-null tests include the estimate and its standard error as well.

The new Kappa regression computes the published SkinCondition matrix and compares *all*
whitespace-delimited tokens of the two complete tables, including the formerly missing estimate.
39 affected local FREQ corpus goldens reflect these rendering changes; oracle expected files
remain unchanged. Numeric comparison of these golden changes preserves all existing estimates,
counts, tests, limits and probabilities: duplicate confidence headers are consolidated; Kappa
hypothesis nulls move from four-decimal fields into headings; test estimates and nonzero-null
standard errors are added. The weighted-missing regression also checks the four missing cells
of the Weighted Kappa row, rather than merely its old table title.

## Full oracle comparison — 2/2 PASS

Each listed SAS case executes independently and unchanged:
`zig-out/bin/opensas --graphics-dir <case-graphs> tests/STAT15.4-oracle/STAT-FREQ-001/<case>.sas`.
Graph directories are fresh for the recorded run. Whitespace normalization is exactly Python
`' '.join(text.split())`: collapse whitespace runs and trim edges. No fields, rules, headings,
tables, numbers, or diagnostics are dropped. Runtime identity comes from the current OpenSAS
build, not a SAS version string; these listings contain no version text, so no substitution occurs.

Both complete listings PASS. Both statuses are 0, matching expected. Actual logs have no warnings
or errors, matching reference warning/error semantics. Actual diagnostics contain three SVG-written
notes per case. Reference startup/source echoes, workspace-deletion notes, observation/read notes
and printed-page notes differ. Reference warning/error semantics and return status were checked;
no exemption for informational logs is claimed. Complete actual diagnostics are retained below.

Counts: first analysis N=223; controlling strata boys=105, girls=118; agreement N=88.
The BY fixture has _oracle_by=1 and _oracle_by=2, each with the full first analysis at N=223.
All 649 non-whitespace tokens in documented_feature and all 803 in statement_by match, in order,
including every table, field, numerical value, and rule.

## Graph inspection

Six SVGs rendered and visually inspected: two clustered frequency plots and an agreement plot
per case. Boys bars (27,29,14,35), girls (23,10,53,32), category labels and legends agree with
inputs. Agreement scale ends at 88. No clipping/overlap observed. Both cases produce identical
sets of plots. After integrating the shared fix, all six SVGs remain byte-identical to those
inspected. No oracle graph images are supplied, so pixel parity is not claimed.
The inspected contact sheet remains dev3-graphs.png; graphics code was not changed.

## documented_feature — complete actual listing

Expected bytes 6367; actual bytes 7027; full normalized text PASS (649 tokens). Expected status 0; actual 0.

```text
                        The FREQ Procedure

                        Table of Internship by Enrollment

              Internship     Enrollment

              Frequency|
              Percent  |
              Row Pct  |
              Col Pct  |yes     |no      |  Total
              ---------+--------+--------+
              yes      |     67 |     39 |    106
                       |  30.04 |  17.49 |  47.53
                       |  63.21 |  36.79 |
                       |  50.00 |  43.82 |
              ---------+--------+--------+
              no       |     67 |     50 |    117
                       |  30.04 |  22.42 |  52.47
                       |  57.26 |  42.74 |
                       |  50.00 |  56.18 |
              ---------+--------+--------+
              Total         134       89      223
                          60.09    39.91   100.00

Statistics for Table of Internship by Enrollment

Statistic                     DF       Value      Prob
------------------------------------------------------
Chi-Square                       1      0.8189    0.3655
Likelihood Ratio Chi-Square      1      0.8202    0.3651
Continuity Adj. Chi-Square       1      0.5899    0.4425
Mantel-Haenszel Chi-Square       1      0.8153    0.3666
Phi Coefficient                         0.0606
Contingency Coefficient                 0.0605
Cramer's V                              0.0606

Fisher's Exact Test
----------------------------------
Cell (1,1) Frequency (F)        67
Left-sided Pr <= F          0.8513
Right-sided Pr >= F         0.2213
Table Probability (P)       0.0726
Two-sided Pr <= P           0.4122

Sample Size = 223
                        The FREQ Procedure

                        Table 1 of Internship by Enrollment
                        Controlling for Gender=boys

              Internship     Enrollment

              Frequency|
              Percent  |
              Row Pct  |
              Col Pct  |no      |yes     |  Total
              ---------+--------+--------+
              no       |     27 |     14 |     41
                       |  25.71 |  13.33 |  39.05
                       |  65.85 |  34.15 |
                       |  48.21 |  28.57 |
              ---------+--------+--------+
              yes      |     29 |     35 |     64
                       |  27.62 |  33.33 |  60.95
                       |  45.31 |  54.69 |
                       |  51.79 |  71.43 |
              ---------+--------+--------+
              Total          56       49      105
                          53.33    46.67   100.00

Statistics for Table 1 of Internship by Enrollment
Controlling for Gender=boys

Statistic                     DF       Value      Prob
------------------------------------------------------
Chi-Square                       1      4.2366    0.0396
Likelihood Ratio Chi-Square      1      4.2903    0.0383
Continuity Adj. Chi-Square       1      3.4515    0.0632
Mantel-Haenszel Chi-Square       1      4.1963    0.0405
Phi Coefficient                         0.2009
Contingency Coefficient                 0.1969
Cramer's V                              0.2009

Fisher's Exact Test
----------------------------------
Cell (1,1) Frequency (F)        27
Left-sided Pr <= F          0.9885
Right-sided Pr >= F         0.0311
Table Probability (P)       0.0196
Two-sided Pr <= P           0.0467

Sample Size = 105


                        Table 2 of Internship by Enrollment
                        Controlling for Gender=girls

              Internship     Enrollment

              Frequency|
              Percent  |
              Row Pct  |
              Col Pct  |no      |yes     |  Total
              ---------+--------+--------+
              no       |     23 |     53 |     76
                       |  19.49 |  44.92 |  64.41
                       |  30.26 |  69.74 |
                       |  69.70 |  62.35 |
              ---------+--------+--------+
              yes      |     10 |     32 |     42
                       |   8.47 |  27.12 |  35.59
                       |  23.81 |  76.19 |
                       |  30.30 |  37.65 |
              ---------+--------+--------+
              Total          33       85      118
                          27.97    72.03   100.00

Statistics for Table 2 of Internship by Enrollment
Controlling for Gender=girls

Statistic                     DF       Value      Prob
------------------------------------------------------
Chi-Square                       1      0.5593    0.4546
Likelihood Ratio Chi-Square      1      0.5681    0.4510
Continuity Adj. Chi-Square       1      0.2848    0.5936
Mantel-Haenszel Chi-Square       1      0.5545    0.4565
Phi Coefficient                         0.0688
Contingency Coefficient                 0.0687
Cramer's V                              0.0688

Fisher's Exact Test
----------------------------------
Cell (1,1) Frequency (F)        23
Left-sided Pr <= F          0.8317
Right-sided Pr >= F         0.2994
Table Probability (P)       0.1311
Two-sided Pr <= P           0.5245

Sample Size = 118
                        The FREQ Procedure

Summary Statistics for Internship by Enrollment
Controlling for Gender

Cochran-Mantel-Haenszel Statistics (Based on Table Scores)
Statistic    Alternative Hypothesis    DF       Value      Prob
---------------------------------------------------------------
        1    Nonzero Correlation       1      4.0186    0.0450
        2    Row Mean Scores Differ    1      4.0186    0.0450
        3    General Association       1      4.0186    0.0450

Common Odds Ratio and Relative Risks
Statistic                 Method               Value    95% Confidence Limits
-------------------------------------------------------------------------------------
Odds Ratio                Mantel-Haenszel      1.8230      1.0095      3.2921
                          Logit                1.8261      1.0112      3.2979
Relative Risk (Column 1)  Mantel-Haenszel      1.3872      1.0099      1.9056
                          Logit                1.4095      1.0384      1.9134
Relative Risk (Column 2)  Mantel-Haenszel      0.7993      0.6398      0.9985
                          Logit                0.8545      0.6971      1.0474

Breslow-Day Test for
Homogeneity of Odds Ratios
--------------------------
Chi-Square                     0.7324
DF                                  1
Pr > ChiSq                     0.3921

Total Sample Size = 223
                        The FREQ Procedure

Statistics for Table of Derm1 by Derm2

Symmetry Test
Chi-Square        DF    Pr > ChiSq
    4.5354         6        0.6046

Kappa Statistics
                              Standard
Statistic         Estimate       Error    95% Confidence Limits
Simple Kappa        0.3449      0.0724      0.2030       0.4868
Weighted Kappa      0.5082      0.0655      0.3798       0.6366

Test of H0: Kappa = 0
Estimate    H0 Std Err           Z    Pr > Z    Pr > |Z|
  0.3449        0.0612      5.6366    <.0001      <.0001

Sample Size = 88
```

Complete actual diagnostics:

```text
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-001/dev3-evidence/documented_feature-graphs/opensas-0001-freqplot.svg.
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-001/dev3-evidence/documented_feature-graphs/opensas-0002-freqplot.svg.
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-001/dev3-evidence/documented_feature-graphs/opensas-0003-agreeplot.svg.
```

Unmodified SAS input SHA256: 4247fd0c5afd80da630325b9535197fbd5c96d173c46f5ee3f4fe8f84d1c69eb

## statement_by — complete actual listing

Expected bytes 7806; actual bytes 8773; full normalized text PASS (803 tokens). Expected status 0; actual 0.

```text

                                  _oracle_by=1
                        The FREQ Procedure

                        Table of Internship by Enrollment

              Internship     Enrollment

              Frequency|
              Percent  |
              Row Pct  |
              Col Pct  |yes     |no      |  Total
              ---------+--------+--------+
              yes      |     67 |     39 |    106
                       |  30.04 |  17.49 |  47.53
                       |  63.21 |  36.79 |
                       |  50.00 |  43.82 |
              ---------+--------+--------+
              no       |     67 |     50 |    117
                       |  30.04 |  22.42 |  52.47
                       |  57.26 |  42.74 |
                       |  50.00 |  56.18 |
              ---------+--------+--------+
              Total         134       89      223
                          60.09    39.91   100.00

Statistics for Table of Internship by Enrollment

Statistic                     DF       Value      Prob
------------------------------------------------------
Chi-Square                       1      0.8189    0.3655
Likelihood Ratio Chi-Square      1      0.8202    0.3651
Continuity Adj. Chi-Square       1      0.5899    0.4425
Mantel-Haenszel Chi-Square       1      0.8153    0.3666
Phi Coefficient                         0.0606
Contingency Coefficient                 0.0605
Cramer's V                              0.0606

Fisher's Exact Test
----------------------------------
Cell (1,1) Frequency (F)        67
Left-sided Pr <= F          0.8513
Right-sided Pr >= F         0.2213
Table Probability (P)       0.0726
Two-sided Pr <= P           0.4122

Sample Size = 223

                                  _oracle_by=2
                        The FREQ Procedure

                        Table of Internship by Enrollment

              Internship     Enrollment

              Frequency|
              Percent  |
              Row Pct  |
              Col Pct  |yes     |no      |  Total
              ---------+--------+--------+
              yes      |     67 |     39 |    106
                       |  30.04 |  17.49 |  47.53
                       |  63.21 |  36.79 |
                       |  50.00 |  43.82 |
              ---------+--------+--------+
              no       |     67 |     50 |    117
                       |  30.04 |  22.42 |  52.47
                       |  57.26 |  42.74 |
                       |  50.00 |  56.18 |
              ---------+--------+--------+
              Total         134       89      223
                          60.09    39.91   100.00

Statistics for Table of Internship by Enrollment

Statistic                     DF       Value      Prob
------------------------------------------------------
Chi-Square                       1      0.8189    0.3655
Likelihood Ratio Chi-Square      1      0.8202    0.3651
Continuity Adj. Chi-Square       1      0.5899    0.4425
Mantel-Haenszel Chi-Square       1      0.8153    0.3666
Phi Coefficient                         0.0606
Contingency Coefficient                 0.0605
Cramer's V                              0.0606

Fisher's Exact Test
----------------------------------
Cell (1,1) Frequency (F)        67
Left-sided Pr <= F          0.8513
Right-sided Pr >= F         0.2213
Table Probability (P)       0.0726
Two-sided Pr <= P           0.4122

Sample Size = 223
                        The FREQ Procedure

                        Table 1 of Internship by Enrollment
                        Controlling for Gender=boys

              Internship     Enrollment

              Frequency|
              Percent  |
              Row Pct  |
              Col Pct  |no      |yes     |  Total
              ---------+--------+--------+
              no       |     27 |     14 |     41
                       |  25.71 |  13.33 |  39.05
                       |  65.85 |  34.15 |
                       |  48.21 |  28.57 |
              ---------+--------+--------+
              yes      |     29 |     35 |     64
                       |  27.62 |  33.33 |  60.95
                       |  45.31 |  54.69 |
                       |  51.79 |  71.43 |
              ---------+--------+--------+
              Total          56       49      105
                          53.33    46.67   100.00

Statistics for Table 1 of Internship by Enrollment
Controlling for Gender=boys

Statistic                     DF       Value      Prob
------------------------------------------------------
Chi-Square                       1      4.2366    0.0396
Likelihood Ratio Chi-Square      1      4.2903    0.0383
Continuity Adj. Chi-Square       1      3.4515    0.0632
Mantel-Haenszel Chi-Square       1      4.1963    0.0405
Phi Coefficient                         0.2009
Contingency Coefficient                 0.1969
Cramer's V                              0.2009

Fisher's Exact Test
----------------------------------
Cell (1,1) Frequency (F)        27
Left-sided Pr <= F          0.9885
Right-sided Pr >= F         0.0311
Table Probability (P)       0.0196
Two-sided Pr <= P           0.0467

Sample Size = 105


                        Table 2 of Internship by Enrollment
                        Controlling for Gender=girls

              Internship     Enrollment

              Frequency|
              Percent  |
              Row Pct  |
              Col Pct  |no      |yes     |  Total
              ---------+--------+--------+
              no       |     23 |     53 |     76
                       |  19.49 |  44.92 |  64.41
                       |  30.26 |  69.74 |
                       |  69.70 |  62.35 |
              ---------+--------+--------+
              yes      |     10 |     32 |     42
                       |   8.47 |  27.12 |  35.59
                       |  23.81 |  76.19 |
                       |  30.30 |  37.65 |
              ---------+--------+--------+
              Total          33       85      118
                          27.97    72.03   100.00

Statistics for Table 2 of Internship by Enrollment
Controlling for Gender=girls

Statistic                     DF       Value      Prob
------------------------------------------------------
Chi-Square                       1      0.5593    0.4546
Likelihood Ratio Chi-Square      1      0.5681    0.4510
Continuity Adj. Chi-Square       1      0.2848    0.5936
Mantel-Haenszel Chi-Square       1      0.5545    0.4565
Phi Coefficient                         0.0688
Contingency Coefficient                 0.0687
Cramer's V                              0.0688

Fisher's Exact Test
----------------------------------
Cell (1,1) Frequency (F)        23
Left-sided Pr <= F          0.8317
Right-sided Pr >= F         0.2994
Table Probability (P)       0.1311
Two-sided Pr <= P           0.5245

Sample Size = 118
                        The FREQ Procedure

Summary Statistics for Internship by Enrollment
Controlling for Gender

Cochran-Mantel-Haenszel Statistics (Based on Table Scores)
Statistic    Alternative Hypothesis    DF       Value      Prob
---------------------------------------------------------------
        1    Nonzero Correlation       1      4.0186    0.0450
        2    Row Mean Scores Differ    1      4.0186    0.0450
        3    General Association       1      4.0186    0.0450

Common Odds Ratio and Relative Risks
Statistic                 Method               Value    95% Confidence Limits
-------------------------------------------------------------------------------------
Odds Ratio                Mantel-Haenszel      1.8230      1.0095      3.2921
                          Logit                1.8261      1.0112      3.2979
Relative Risk (Column 1)  Mantel-Haenszel      1.3872      1.0099      1.9056
                          Logit                1.4095      1.0384      1.9134
Relative Risk (Column 2)  Mantel-Haenszel      0.7993      0.6398      0.9985
                          Logit                0.8545      0.6971      1.0474

Breslow-Day Test for
Homogeneity of Odds Ratios
--------------------------
Chi-Square                     0.7324
DF                                  1
Pr > ChiSq                     0.3921

Total Sample Size = 223
                        The FREQ Procedure

Statistics for Table of Derm1 by Derm2

Symmetry Test
Chi-Square        DF    Pr > ChiSq
    4.5354         6        0.6046

Kappa Statistics
                              Standard
Statistic         Estimate       Error    95% Confidence Limits
Simple Kappa        0.3449      0.0724      0.2030       0.4868
Weighted Kappa      0.5082      0.0655      0.3798       0.6366

Test of H0: Kappa = 0
Estimate    H0 Std Err           Z    Pr > Z    Pr > |Z|
  0.3449        0.0612      5.6366    <.0001      <.0001

Sample Size = 88
```

Complete actual diagnostics:

```text
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-001/dev3-evidence/statement_by-graphs/opensas-0001-freqplot.svg.
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-001/dev3-evidence/statement_by-graphs/opensas-0002-freqplot.svg.
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-001/dev3-evidence/statement_by-graphs/opensas-0003-agreeplot.svg.
```

Unmodified SAS input SHA256: 3f2fd0f3d54dbc8ac9eced03826091faf97fb6249c77aedb3111343e7c38d4c5

## Continued-attempt changed files

- `README.md`
- `src/main.zig`
- `src/proc.zig`
- `src/stat/data_selection.zig`
- `src/stat/freq.zig`
- `src/stat/freq_stratified_execute.zig`
- `src/stat/freq_stratified_render.zig`
- `src/stat/reg_fit.zig`
- `stat-jira.md`
- `tests/STAT15.4-oracle/STAT-COMMON-002/implementation-evidence.md`
- `tests/STAT15.4-oracle/STAT-FREQ-001/dev3-attempt.md`
- `tests/corpus/freq_missing_strata.txt`
- `tests/corpus/freq_nway_out.txt`
- `tests/corpus/freq_risk_aliases_public.txt`
- `tests/corpus/freq_risk_boundaries_public.txt`
- `tests/corpus/freq_risk_equality_public.txt`
- `tests/corpus/freq_risk_gap_common.txt`
- `tests/corpus/freq_risk_high_alpha_public.txt`
- `tests/corpus/freq_risk_inference_public.txt`
- `tests/corpus/freq_risk_infinite_fractional_public.txt`
- `tests/corpus/freq_risk_ni_sup_public.txt`
- `tests/corpus/freq_risk_twoway_public.txt`
- `tests/corpus/freq_stmt_opts.txt`
- `tests/corpus/freq_strata_order.txt`
- `tests/corpus/freq_stratified_agree_edges.txt`
- `tests/corpus/freq_stratified_all.txt`
- `tests/corpus/freq_stratified_by.txt`
- `tests/corpus/freq_stratified_cmh.txt`
- `tests/corpus/freq_stratified_common.txt`
- `tests/corpus/freq_stratified_descending_weights.txt`
- `tests/corpus/freq_stratified_details.txt`
- `tests/corpus/freq_stratified_dfsym.txt`
- `tests/corpus/freq_stratified_examples.txt`
- `tests/corpus/freq_stratified_fractional_alpha.txt`
- `tests/corpus/freq_stratified_gailsimon.txt`
- `tests/corpus/freq_stratified_i2_zero.txt`
- `tests/corpus/freq_stratified_inheritance.txt`
- `tests/corpus/freq_stratified_missing.txt`
- `tests/corpus/freq_stratified_options.txt`
- `tests/corpus/freq_stratified_restore.txt`
- `tests/corpus/freq_stratified_scores.txt`
- `tests/corpus/freq_stratified_sparse.txt`
- `tests/corpus/freq_stratified_weighted_missing.txt`
- `tests/corpus/freq_stratified_weights.txt`
- `tests/corpus/freq_table_displays.txt`
- `tests/corpus/freq_tests_by_strata.txt`
- `tests/corpus/freq_tests_gap_agree.txt`
- `tests/corpus/freq_tests_noprint.txt`
- `tests/corpus/freq_tests_scores.txt`
- `tests/corpus/freq_tests_test_requests.txt`
- `tests/corpus/means_by_emptygroup.txt`
- `tests/corpus/means_by_multivar.txt`
- `tests/corpus/means_stmt_replace.txt`
- `tests/corpus/proc_inf.txt`
- `tests/corpus/proc_means_multi.txt`
- `tests/corpus/proc_means_var.txt`
- `tests/corpus/sdtm_stat_multivar.txt`
- `tests/corpus/stat_common002_weight_roles.sas`
- `tests/corpus/stat_common002_weight_roles.txt`
- `tests/corpus/var_colon_prefix_procs.txt`
