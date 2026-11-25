# dev3 — STAT-FREQ-003 TABLES verification

Result: existing implementation satisfies this ticket's scoped TABLES behavior; evidence-only
completion. No source, new regression, or golden changes. Individual statistical methods,
intervals and graphics options remain the responsibility of their corresponding feature tickets;
this result does not assert every option in the full chapter is implemented.

Branch: codex/stat-dev3. Starting base after the manager's explicit claim and clean tracked-tree
fast-forward: 7087a375848f27c6b221cca579d6f3f22e31a47e. The previously collected raw evidence was
preserved, then the ticket's unchanged oracle was run again after the claim against the rebuilt
binary. Final SHA/base and exact-SHA gate counts are in the handoff. No board/skill edits or push.

## References and scope

Read this ticket's full stat-jira.md entry, its own README and documented_feature.sas. Read
manual physical pages 3106–3154 in
/Users/thomas/kirha/opensas/docs/SAS-STAT-15.4-Users-Guide.pdf. The scoped rules include:

- Requests are one variable or star-crossed variables; the last variable forms columns, the
  penultimate variable rows, and earlier variables form strata.
- Parenthesized variable lists distribute in the documented order; multiple TABLES statements
  and multiple requests are supported. For (A B)*(C D), order is A*C, B*C, A*D, B*D.
- Formatted values determine levels; internal order is default and ORDER changes displayed order.
- Default missing exclusion, MISSING and MISSPRINT use different percentage denominators.
- LIST, CROSSLIST, SPARSE, NOSPARSE and WEIGHT/ZEROS govern zero-frequency combinations.
- Default cells show frequency, total percentage, row percentage and column percentage;
  one-way displays include cumulative frequency/percentage. OUT= uses the final request.

## Own unchanged oracle

Command:
`zig-out/bin/opensas --graphics-dir tests/STAT15.4-oracle/STAT-FREQ-003/dev3-evidence/claimed-graphs tests/STAT15.4-oracle/STAT-FREQ-003/documented_feature.sas`

Expected and actual status: 0. Complete listing PASS, all 649 non-whitespace tokens in order.
Only normalization: Python `' '.join(text.split())` (collapse whitespace runs; trim edges).
No table, header, rule, field, value, or diagnostic was omitted. Runtime identity uses the current
OpenSAS build; no SAS-version substitution was used or needed in this listing.

Actual and reference logs have no warnings/errors. Actual logs contain three SVG-written notes,
reproduced below. Informational SAS startup/source echoes, data/read counts, workspace deletion
and page notes differ. Warning/error semantics and return status were checked; no informational
log exemption is claimed.

The first weighted table has cells [[67,39],[67,50]], row margins [106,117], column margins
[134,89], N=223. The Gender strata have N=105 and 118; agreement N=88. All percentages,
statistics and remaining fields also participate in the complete listing comparison.

## Scoped existing regression coverage

All seven following existing corpus programs were executed unchanged after the claim. Every
complete output matched its existing golden (whitespace-only comparison), every status was 0,
and every stderr stream was empty. They also remain part of `zig build gate`.

| Existing case | TABLES behavior checked |
|---|---|
| freq_tables_paren.sas | One-way grouped `(a b)`, distributed `(a b)*c`, separate TABLES requests and ordinary crossings |
| freq_nway_out.sas | Three-way strata, every cell/margin/percentage, zero cell in display and omission from default OUT= |
| freq_strata_order.sas | ORDER=FREQ, ORDER=DATA and default internal ordering of strata |
| freq_missing_strata.sas | Default exclusion of missing controls versus MISSING creating a missing stratum |
| freq_weight_zeros.sas | Zero-only level exclusion/inclusion, weighted counts, formatted ascending order |
| freq_fmt_freqtie.sas | Formatted labels break frequency ties and descending unequal frequencies |
| freq_table_displays.sas | Four-way nested control strata, LIST/CROSSLIST, SPARSE/NOSPARSE, missing displays, margins, residual/expected cells, MAXLEVELS and display suppression |

Independent count checks for freq_nway_out: a1 is [[1,1],[1,1]], with row margins [2,2],
column margins [2,2], stratum N=4. a2 is [[2,0],[1,1]], with row margins [2,2], column
margins [3,1], stratum N=4. Cell percentages for a2 are [50,0,25,25]; column totals are
[75,25] percent. The OUT= percentages use the whole N=8 (12.5% for singleton cells and
25% for the cell with count 2), and its seven rows omit the empty cell. Complete output below.

For freq_weight_zeros, independent weighted totals are A=4, B=3, C=0 (N=7). C is omitted by
default and retained by ZEROS; formatted order becomes Alpha(C), Mid(B), Zed(A). For
freq_missing_strata, the two missing-control observations are excluded by default and form
a separate stratum with MISSING. For freq_strata_order, Z has 3 observations and A has 2;
FREQ/DATA put Z first and INTERNAL puts A first. These checks agree with all displayed cells.

Existing captured-diagnostic unit coverage in src/stat/freq.zig rejects malformed/empty table
specifications and conflicting LIST/CROSSLIST or SPARSE/NOSPARSE requests. The existing
Cartesian-ordering test checks `(x01-x02)*(x03--x04)` expands to four requests in the documented
order and only the final request receives OUT=. The typed global-level/sparse-strata test pins
all 16 four-way cells, empty strata, weighted totals and negative-weight behavior. Existing
MISSPRINT and weighted-table metric tests check percentage bases and individual cell metrics.
These tests already cover the assigned behavior, so no duplicate regression was introduced.

## Graph inspection

The post-claim oracle generated three fresh SVGs, rendered and visually inspected in dev3-graphs.png.
The boys and girls clustered charts show counts [27,29,14,35] and [23,10,53,32]; category order,
axis labels and legends agree with the tables. The agreement plot shows ordered ratings
terrible/poor/marginal/clear, exact/partial agreement and a cumulative-frequency scale to 88.
No clipping or overlap observed. Palette, fonts, subtitle wording, legend placement and tick
increments differ from SAS manual styling; no pixel-identical claim is made. No saved oracle
graph files are supplied. All three complete plots were inspected.

## Complete actual oracle listing

Expected bytes 6367; actual bytes 7027; full normalized comparison PASS.

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

## Complete actual oracle diagnostics

```text
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-003/dev3-evidence/claimed-graphs/opensas-0001-freqplot.svg.
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-003/dev3-evidence/claimed-graphs/opensas-0002-freqplot.svg.
NOTE: SVG graphic written to tests/STAT15.4-oracle/STAT-FREQ-003/dev3-evidence/claimed-graphs/opensas-0003-agreeplot.svg.
```

## Complete independent multiway regression output

```text
                        The FREQ Procedure

                        Table 1 of b by c
                        Controlling for a=a1

              b         c

              Frequency|
              Percent  |
              Row Pct  |
              Col Pct  |c1      |c2      |  Total
              ---------+--------+--------+
              b1       |      1 |      1 |      2
                       |  25.00 |  25.00 |  50.00
                       |  50.00 |  50.00 |
                       |  50.00 |  50.00 |
              ---------+--------+--------+
              b2       |      1 |      1 |      2
                       |  25.00 |  25.00 |  50.00
                       |  50.00 |  50.00 |
                       |  50.00 |  50.00 |
              ---------+--------+--------+
              Total           2        2        4
                          50.00    50.00   100.00


                        Table 2 of b by c
                        Controlling for a=a2

              b         c

              Frequency|
              Percent  |
              Row Pct  |
              Col Pct  |c1      |c2      |  Total
              ---------+--------+--------+
              b1       |      2 |      0 |      2
                       |  50.00 |   0.00 |  50.00
                       | 100.00 |   0.00 |
                       |  66.67 |   0.00 |
              ---------+--------+--------+
              b2       |      1 |      1 |      2
                       |  25.00 |  25.00 |  50.00
                       |  50.00 |  50.00 |
                       |  33.33 | 100.00 |
              ---------+--------+--------+
              Total           3        1        4
                          75.00    25.00   100.00
Obs   a    b    c    count_   PERCENT

  1   a1   b1   c1        1      12.5
  2   a1   b1   c2        1      12.5
  3   a1   b2   c1        1      12.5
  4   a1   b2   c2        1      12.5
  5   a2   b1   c1        2        25
  6   a2   b2   c1        1      12.5
  7   a2   b2   c2        1      12.5
```

Oracle input SHA256: db8643cc2abcde468a3b56ff2fc38feedbef4f7d62fe9a7f644604b3aec1060c
