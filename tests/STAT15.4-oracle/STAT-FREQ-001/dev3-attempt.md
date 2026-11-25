# dev3 — STAT-FREQ-001 bounded attempt: PARK, partial fix

Baseline: c2bc2789f9b89415260bb50c8939bebe6f88dca8. Branch: codex/stat-dev3.
Rebased onto local feat/stat15.4-tickets at 1d5da736ce28e352cf865bfac9fd35b6f1b0a641.
Runtime/source checked: SHA ac01b91b06fb3940f427c1989ebe88f0a9d4ae77. No oracle inputs or expected files changed.

Read CLAUDE.md, src/lexer.zig, applicable decisions (especially D-002/003/009/017/018/029), ticket entry and README.
Read physical PDF pages 3082–3085 and 3157–3162 from the shared manual at
/Users/thomas/kirha/opensas/docs/SAS-STAT-15.4-Users-Guide.pdf (manual absent in this worktree).
Reused existing FREQ runtime, BY and numeric-role/weight APIs; no shared implementation edits.

## Shipped partial fix

Grid headings were positioned from the width of row *values*, so Internship and Enrollment
ran together, and longer names were overwritten. Move the column heading only when the
unlabelled variable names would collide. Keep frequency cells and existing separated headings
unchanged. A unit regression exercises both the oracle names and a longer row name, and checks
that the data-column headings remain intact.

Initial gate exposed an unnecessary spacing change for Adverse/Dose; narrowed the condition
without changing that fixture. Corrected gate: 18/18 steps, 1589/1589 unit tests,
2301/2301 corpus, 11/11 programs, exit 0. Full gate output below.

## Oracle comparison — 0/2 pass

Both listed SAS programs executed unchanged, independently, using the freshly rebuilt binary:
`zig-out/bin/opensas --graphics-dir <case-graphs> tests/STAT15.4-oracle/STAT-FREQ-001/<case>.sas`.
Each graph directory was emptied before the final execution.
Only normalization: Python `' '.join(text.split())`, collapsing whitespace runs (including
newlines) to single spaces and trimming ends. No headings, rules, fields, tables, numbers,
or diagnostics were removed. Current OpenSAS version identity is permitted; neither listing
contains a version string, so no version substitution was needed.

Both statuses: actual 1, expected 0. Both complete whitespace-normalized listings differ.
The shared prelude reports `ERROR(expanded L5): system option validmemname is not recognized`.
Dev2 exclusively owns this fix; it is not integrated in the checked base. Do not mark DONE
without rerunning the unchanged cases after integration.

All displayed counts, percentages, test statistics, p-values, confidence limits and sample sizes
match the corresponding expected values. Counts are 223 overall; boys 105, girls 118;
agreement sample size 88. BY case correctly repeats the first analysis for _oracle_by=1 and 2,
each N=223. This numerical correspondence is NOT full text/field parity:

- Extra procedure heading before stratum 2; missing procedure heading before CMH summary.
- Missing rule beneath common odds/relative-risk header.
- Breslow–Day is horizontal instead of the expected vertical layout and lacks its rule.
- Extra `Table of Derm1 by Derm2` heading despite TABLES NOPRINT.
- Expected combined Kappa Statistics table is split into Simple/Weighted Kappa Coefficient tables.
- Expected `Test of H0: Kappa = 0` table is rendered as `Kappa Test`, with an extra Null Value
  field and without the expected Estimate=0.3449 field in that test table. The estimate appearing
  in the preceding statistics table does not substitute for the omitted field.
- Logs differ: actual contains the prelude error and three SVG-written notes. Reference logs
  contain SAS source echoes, workspace-deletion notes, INPUT/read/data-set observation notes,
  and printed-page notes absent from actual. No reference ERROR/WARNING was found. These
  diagnostics are retained as differences, not filtered to manufacture parity.

PARK reason: complete parity requires broader statistical rendering/field and shared diagnostic
work beyond this narrow declaration/input attempt. The acceptance matrix is not claimed complete.
No backlog expansion, no expected-output changes, no board or skill edits, no push.

## Graph inspection

Six SVGs rendered and visually inspected (three per unchanged case). Both sets show the boys
and girls clustered frequency charts plus the agreement chart. Boys bars (27,29,14,35), girls
(23,10,53,32), category labels, legends and agreement cumulative scale ending at 88 agree with
inputs. No clipping/overlap observed. Matching plots in the two cases are identical. No saved
oracle graph images are supplied, so pixel parity is not claimed. Contact sheet: dev3-graphs.png.

## documented_feature — complete actual output

Expected listing bytes: 6367; actual: 7012. Expected rc=0; actual rc=1.

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

                        The FREQ Procedure

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
Odds Ratio                Mantel-Haenszel      1.8230      1.0095      3.2921
                          Logit                1.8261      1.0112      3.2979
Relative Risk (Column 1)  Mantel-Haenszel      1.3872      1.0099      1.9056
                          Logit                1.4095      1.0384      1.9134
Relative Risk (Column 2)  Mantel-Haenszel      0.7993      0.6398      0.9985
                          Logit                0.8545      0.6971      1.0474

Breslow-Day Test for Homogeneity of Odds Ratios
Chi-Square        DF    Pr > ChiSq
    0.7324         1        0.3921

Total Sample Size = 223
                        The FREQ Procedure

                        Table of Derm1 by Derm2


Statistics for Table of Derm1 by Derm2

Symmetry Test
Chi-Square        DF    Pr > ChiSq
    4.5354         6        0.6046

Simple Kappa Coefficient
Estimate       Standard Error    95% Confidence Limits
    0.3449             0.0724       0.2030       0.4868

Weighted Kappa Coefficient
Estimate       Standard Error    95% Confidence Limits
    0.5082             0.0655       0.3798       0.6366

Kappa Test
Null Value                     0.0000
H0 Std Err                     0.0612
Z                              5.6366
Pr > Z                         <.0001
Pr > |Z|                       <.0001

Sample Size = 88
```

Complete actual diagnostics:

```text
ERROR(expanded L5): system option validmemname is not recognized
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-001/dev3-evidence/documented_feature-graphs/opensas-0001-freqplot.svg.
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-001/dev3-evidence/documented_feature-graphs/opensas-0002-freqplot.svg.
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-001/dev3-evidence/documented_feature-graphs/opensas-0003-agreeplot.svg.
```

Complete non-whitespace token differences (expected → actual):

- '' → 'The FREQ Procedure'
- 'The FREQ Procedure' → ''
- '-------------------------------------------------------------------------------------' → ''
- '--------------------------' → ''
- '0.7324' → ''
- '1' → ''
- '' → '0.7324 1'
- '' → 'Table of Derm1 by Derm2'
- '' → 'Simple'
- 'Statistics' → 'Coefficient Estimate'
- 'Statistic Estimate' → ''
- 'Simple Kappa' → ''
- '' → 'Coefficient Estimate Standard Error 95% Confidence Limits'
- '' → 'Kappa'
- 'of H0: Kappa = 0 Estimate' → 'Null Value 0.0000'
- '' → '0.0612'
- '' → '5.6366'
- '' → '<.0001'
- '0.3449 0.0612 5.6366 <.0001' → ''

Input SHA256: 4247fd0c5afd80da630325b9535197fbd5c96d173c46f5ee3f4fe8f84d1c69eb

## statement_by — complete actual output

Expected listing bytes: 7806; actual: 8758. Expected rc=0; actual rc=1.

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

                        The FREQ Procedure

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
Odds Ratio                Mantel-Haenszel      1.8230      1.0095      3.2921
                          Logit                1.8261      1.0112      3.2979
Relative Risk (Column 1)  Mantel-Haenszel      1.3872      1.0099      1.9056
                          Logit                1.4095      1.0384      1.9134
Relative Risk (Column 2)  Mantel-Haenszel      0.7993      0.6398      0.9985
                          Logit                0.8545      0.6971      1.0474

Breslow-Day Test for Homogeneity of Odds Ratios
Chi-Square        DF    Pr > ChiSq
    0.7324         1        0.3921

Total Sample Size = 223
                        The FREQ Procedure

                        Table of Derm1 by Derm2


Statistics for Table of Derm1 by Derm2

Symmetry Test
Chi-Square        DF    Pr > ChiSq
    4.5354         6        0.6046

Simple Kappa Coefficient
Estimate       Standard Error    95% Confidence Limits
    0.3449             0.0724       0.2030       0.4868

Weighted Kappa Coefficient
Estimate       Standard Error    95% Confidence Limits
    0.5082             0.0655       0.3798       0.6366

Kappa Test
Null Value                     0.0000
H0 Std Err                     0.0612
Z                              5.6366
Pr > Z                         <.0001
Pr > |Z|                       <.0001

Sample Size = 88
```

Complete actual diagnostics:

```text
ERROR(expanded L5): system option validmemname is not recognized
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-001/dev3-evidence/statement_by-graphs/opensas-0001-freqplot.svg.
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-001/dev3-evidence/statement_by-graphs/opensas-0002-freqplot.svg.
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-001/dev3-evidence/statement_by-graphs/opensas-0003-agreeplot.svg.
```

Complete non-whitespace token differences (expected → actual):

- '' → 'The FREQ Procedure'
- 'The FREQ Procedure' → ''
- '-------------------------------------------------------------------------------------' → ''
- '--------------------------' → ''
- '0.7324' → ''
- '1' → ''
- '' → '0.7324 1'
- '' → 'Table of Derm1 by Derm2'
- '' → 'Simple'
- 'Statistics' → 'Coefficient Estimate'
- 'Statistic Estimate' → ''
- 'Simple Kappa' → ''
- '' → 'Coefficient Estimate Standard Error 95% Confidence Limits'
- '' → 'Kappa'
- 'of H0: Kappa = 0 Estimate' → 'Null Value 0.0000'
- '' → '0.0612'
- '' → '5.6366'
- '' → '<.0001'
- '0.3449 0.0612 5.6366 <.0001' → ''

Input SHA256: 3f2fd0f3d54dbc8ac9eced03826091faf97fb6249c77aedb3111343e7c38d4c5

## Corrected gate transcript

```text
corpus: 2301/2301 passing
programs: 11/11 passing
Build Summary: 18/18 steps succeeded; 1589/1589 tests passed
gate success
+- test success
|  +- run test 1484 pass (1484 total) 29s MaxRSS:115M
|  |  +- compile test Debug native success 32s MaxRSS:1G
|  +- run test 91 pass (91 total) 797ms MaxRSS:17M
|  |  +- compile test Debug native success 20s MaxRSS:1G
|  |     +- options success
|  +- run test 11 pass (11 total) 22ms MaxRSS:3M
|  |  +- compile test Debug native cached 80ms MaxRSS:38M
|  +- run test 3 pass (3 total) 18ms MaxRSS:3M
|     +- compile test Debug native cached 88ms MaxRSS:38M
+- corpus success
|  +- run exe corpus_runner success 15s
|     +- compile exe corpus_runner Debug native cached 83ms MaxRSS:38M
|     +- compile exe opensas Debug native success 19s MaxRSS:1G
|        +- options (reused)
+- programs success
   +- run exe programs_runner success 241ms
      +- compile exe programs_runner Debug native cached 86ms MaxRSS:38M
      +- compile exe opensas Debug native (+1 more reused dependencies)

```
