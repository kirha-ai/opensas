/* STAT-FREQ-015: Gail-Simon test for qualitative interactions, hand-derived.
 * SAS/STAT 15.4 PROC FREQ "Gail-Simon Test for Qualitative Interactions" and
 * the TABLES GAILSIMON<(COLUMN=1|2)> / GS option. Invented data. Expected
 * words come from the rational derivation below, not from OpenSAS output.
 *
 * Column 1 risk difference d = n11/n1. - n21/n2., s^2 = p1(1-p1)/n1. + p2(1-p2)/n2.:
 *   s=1: 3 1 / 1 3  d =  1/2  s^2 = 3/32  (d/s)^2 = 8/3
 *   s=2: 1 4 / 3 2  d = -2/5  s^2 = 2/25  (d/s)^2 = 2
 *   s=3: 2 2 / 1 3  d =  1/4  s^2 = 7/64  (d/s)^2 = 4/7
 * Q+ = 8/3 + 4/7 = 68/21 = 3.2381, Q- = 2, Q = min = 2, q = 3 strata.
 * With T1(x) = erfc(sqrt(x/2)), T2(x) = exp(-x/2), T3(x) = T1 + sqrt(2x/pi) exp(-x/2):
 *   P(Q+) = (3 T1 + 3 T2 + T3)(68/21) / 8 = (3(0.071944) + 3(0.198087) + 0.356352)/8 = 0.1458
 *   P(Q-) = (3 T1 + 3 T2 + T3)(2) / 8     = (3(0.157299) + 3(0.367879) + 0.572407)/8 = 0.2685
 *   P(Q)  = T1(2)/2 + T2(2)/4             = 0.078650 + 0.091970                      = 0.1706
 * COLUMN=2 negates every d with the same s: Q+ and Q- exchange.
 * Step 4 (dataset tie): 2 2 / 3 3 has d = 0 and counts in q only; with
 *   1 4 / 3 2: Q+ = 0 (P = 1/2 + 1/4 = 0.7500), Q- = 2 (P = T1(2)/2 + T2(2)/4
 *   = 0.1706), Q = 0 (P = 1/2).
 * Step 5: one stratum, and step 6: 2x3 strata -- the test applies only to two
 *   or more 2x2 strata, so no Gail-Simon table is displayed (NOPRINT leaves
 *   no other output for these two steps).
 */
options nosyntaxcheck; ods graphics off;
data three; input s r c n @@; datalines;
1 1 1 3 1 1 2 1 1 2 1 1 1 2 2 3
2 1 1 1 2 1 2 4 2 2 1 3 2 2 2 2
3 1 1 2 3 1 2 2 3 2 1 1 3 2 2 3
;
proc freq data=three; tables s*r*c / gailsimon noprint; weight n; run;
proc freq data=three; tables s*r*c / gs(column=2) noprint; weight n; run;
proc freq data=three; tables s*r*c / GailSimon(Column=1) noprint; weight n; run;
data tie; input s r c n @@; datalines;
1 1 1 2 1 1 2 2 1 2 1 3 1 2 2 3
2 1 1 1 2 1 2 4 2 2 1 3 2 2 2 2
;
proc freq data=tie; tables s*r*c / gailsimon noprint; weight n; run;
proc freq data=three(where=(s=1)); tables s*r*c / gailsimon noprint; weight n; run;
data wide; input s r c n @@; datalines;
1 1 1 3 1 1 2 1 1 1 3 2 1 2 1 1 1 2 2 3 1 2 3 2
2 1 1 1 2 1 2 4 2 1 3 2 2 2 1 3 2 2 2 2 2 2 3 2
;
proc freq data=wide; tables s*r*c / gailsimon noprint; weight n; run;
