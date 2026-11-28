/* expect-rc: 1
 * STAT-STEPDISC-001: roles and basic options, expected listing from a SAS 9.4
 * run of this program, minus the blank line SAS writes before each
 * procedure's first page (opensas convention).
 * Q1: VAR subset, SLE=0.6 SLS=0.4; entry stops when the best candidate's
 *     Pr > F exceeds SLENTRY ("No variables can be entered.").
 * Q2: numeric CLASS, FREQ (0 drops, 2.7 truncates to 2) and WEIGHT (negative
 *     drops) with a missing VAR value and a missing CLASS value: the four
 *     exclusion WARNINGs and the Sum of Frequencies/Weights rows.
 * Q3: SHORT keeps the first page and the summary only.
 * Q4: candidates listed in VAR order, SLE=0.05.
 * R1: SLSTAY= alone also sets SLENTRY= (and SLENTRY= alone sets SLSTAY=, Q4).
 * R2: SLSTAY=0 removes the variable just entered, leaving an empty model:
 *     SAS stops there and the summary row has no multivariate statistics.
 * SASHELP.FISH is published sample data; the plants rows are invented.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title 'Q1';
data fishn; set sashelp.fish; noise=mod(_n_*37,11); noise2=mod(_n_*53,7); run;
proc stepdisc data=fishn sle=0.6 sls=0.4; class species; var Weight Width noise noise2; run;
title 'Q2';
data plants;
  input g x1 x2 x3 f w;
  datalines;
1 2.1 3.5 1.0 1 1.0
1 2.5 3.1 1.4 2 0.5
1 1.9 3.9 0.8 1 1.5
1 2.8 3.3 1.9 1 1.0
1 2.2 . 1.1 1 1.0
2 3.9 2.2 2.5 1 2.0
2 4.4 2.0 2.9 3 1.0
2 3.6 2.9 2.1 1 1.0
2 4.1 2.4 3.3 0 0.5
3 5.2 4.1 1.2 2 1.0
3 5.9 4.6 0.7 1 -1
3 6.3 3.8 1.6 1 1.5
3 5.5 4.9 1.1 2.7 1.0
3 5.0 4.0 1.3 1 1.0
. 4.0 3.0 2.0 1 1.0
;
proc stepdisc data=plants; class g; freq f; weight w; var x1 x2 x3; run;
title 'Q3';
proc stepdisc data=sashelp.fish short; class species; var height width; run;
title 'Q4';
proc stepdisc data=fishn sle=0.05; class species; var noise noise2 height; run;
title 'R1';
proc stepdisc data=sashelp.fish sls=0.3; class species; var height width; run;
title 'R2';
data nums; input g y1 y2 @@; datalines;
1 1 2 1 2 3 1 3 3 1 2 1 2 5 4 2 6 6 2 5 5 2 7 4 3 9 1 3 8 2 3 9 3 3 10 2
;
proc stepdisc data=nums sle=1 sls=0; class g; var y1 y2; run;
