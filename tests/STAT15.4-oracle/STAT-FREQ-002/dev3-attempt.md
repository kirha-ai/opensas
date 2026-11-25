# dev3 — STAT-FREQ-002 independent oracle verification

Result: already implemented; evidence-only completion. No source or golden changes and no
new regression needed: existing gate cases cover the documented default path and smaller
independent calculations. This ticket's own oracle was executed independently; FREQ-001's
result was not used as a substitute.

Branch: codex/stat-dev3. Starting base after `git merge --ff-only feat/stat15.4-tickets`:
2976ee12719654dbd11cb902ff59b4bb4d1f649c. Final SHA/base and exact-SHA gate counts are
reported in the handoff. Existing probability/statistic routines were reused while COMMON-005
TTEST integration remained pending. No board, skill, shared runtime or other PROC edits; no push.

## Ticket references

Read the full STAT-FREQ-002 entry in stat-jira.md and this directory's README and unchanged SAS.
Read manual physical pages 3070–3081 and 187–198 from
/Users/thomas/kirha/opensas/docs/SAS-STAT-15.4-Users-Guide.pdf. These explain frequency and
contingency tables, sampling assumptions, the SummerSchool default CHISQ analysis, the
Gender-controlled CMH analysis, and the SkinCondition agreement analysis. Inspected the
manual's graph figures on physical pages 3076, 3077 and 3081 alongside this run's rendered SVGs.

## Unchanged oracle execution

Command:
`zig-out/bin/opensas --graphics-dir tests/STAT15.4-oracle/STAT-FREQ-002/dev3-evidence/graphs tests/STAT15.4-oracle/STAT-FREQ-002/documented_default.sas`

Expected status 0; actual status 0. Full listing comparison PASS: all 649 non-whitespace tokens
match in order. The only text normalization is Python `' '.join(text.split())`, collapsing
whitespace runs and trimming edges. No tables, headings, rules, fields, numbers or diagnostics
were dropped. Current OpenSAS runtime identity is used; this listing contains no version string.

Actual and reference logs both contain zero warnings/errors. Actual informational diagnostics
are the three SVG-written notes reproduced below. SAS startup/source-echo, workspace deletion,
observation/read and printed-page notes differ; these differences are disclosed and are not
claimed as authorized exemptions. Return status and warning/error semantics were checked.

Principal results: total weighted N=223; first table counts [[67,39],[67,50]];
Pearson chi-square=0.8189, df=1, p=0.3655; Fisher two-sided p=0.4122.
Boys N=105 and girls N=118; CMH statistics=4.0186, df=1, p=0.0450.
Agreement N=88; simple kappa=0.3449, SE=0.0724, CI [0.2030,0.4868]; weighted kappa=0.5082.
Every other displayed number and field also participates in the full comparison below.

## Existing smaller regressions and independent calculations

Executed unchanged `tests/corpus/freq_weight_twoway.sas`: status 0, no diagnostics, complete
output matches its existing golden. Cells [[2,1],[1,2]] sum to N=6. Both row and column totals
are 3; cell percentages are 100*2/6=33.33 and 100*1/6=16.67; row/column percentages are
66.67 and 33.33. Marginal percentages are 50.00, grand total 100.00. Its complete output is below.

The existing `FEAT-freq-tests exact tails and signed 2x2 association` unit test in
src/stat/freq_tests.zig uses [[1,9],[11,3]], N=24, row totals [10,14], column totals [12,12].
Independent expected cells are [[5,5],[7,7]], so Pearson chi-square is
16/5+16/5+16/7+16/7 = 384/35 = 10.971428571428572. For fixed margins,
P(X=x)=C(12,x)*C(12,10-x)/C(24,10). Summing probabilities no greater than P(X=1)
gives exactly 41/14858 = 0.0027594561852200836. These agree with the existing unit pins
(tolerances 1e-10 for chi-square, 1e-12 for Fisher), which the final gate executes.

The existing `FEAT-freq-tests expected frequencies validate totals and df` one-way unit test
uses counts [20,27,23] and null proportions [20,30,50] percent. Expected counts [14,21,35]
give chi-square 36/14+36/21+144/35=8.4, matching the 1e-12 unit pin.
The corpus `freq_tests_association.sas` and `freq_tests_expected.sas` exercise the public
procedure path for these counts, expected proportions/frequencies and display precision.
The existing weighted-table metrics test in src/stat/freq_table.zig also pins cell expected
counts, chi-square contribution, and total/row/column percentages independently.

## Graph inspection

The fresh run generated and rendered three SVGs; see dev3-graphs.png. Inspected both clustered
bar charts and the agreement chart. Boys bars [27,29,14,35] and girls [23,10,53,32] agree with
the manual; category order, series, legends, and axes convey the same data. The agreement chart
uses terrible/poor/marginal/clear in order and represents N=88 with exact/partial agreement.
No clipping or overlap observed. Styling is not pixel-identical to the manual: palette, fonts,
subtitle spelling (`Gender = ...` versus `Controlling for Gender=...`), legend placement and
agreement tick increments (22 versus 20) differ. No saved oracle graph files are supplied;
pixel parity is not claimed. No graph fields or data series were excluded from inspection.

## Complete actual oracle listing

Expected bytes 6367; actual bytes 7027; normalized comparison PASS.

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

## Complete actual diagnostics

```text
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-002/dev3-evidence/graphs/opensas-0001-freqplot.svg.
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-002/dev3-evidence/graphs/opensas-0002-freqplot.svg.
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-002/dev3-evidence/graphs/opensas-0003-agreeplot.svg.
```

## Complete smaller-case output

```text
                        The FREQ Procedure

                        Table of r by c

              r         c

              Frequency|
              Percent  |
              Row Pct  |
              Col Pct  |c1      |c2      |  Total
              ---------+--------+--------+
              r1       |      2 |      1 |      3
                       |  33.33 |  16.67 |  50.00
                       |  66.67 |  33.33 |
                       |  66.67 |  33.33 |
              ---------+--------+--------+
              r2       |      1 |      2 |      3
                       |  16.67 |  33.33 |  50.00
                       |  33.33 |  66.67 |
                       |  33.33 |  66.67 |
              ---------+--------+--------+
              Total           3        3        6
                          50.00    50.00   100.00
```

Input SHA256: 17d3cce33a87d755ee2382fbdb2aaea37368d7095060f39e0dca51df583b843f
