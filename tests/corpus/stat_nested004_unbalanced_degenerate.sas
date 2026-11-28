/* expect-rc: 1
 * STAT-NESTED-004: the Computational Method in degenerate unbalanced
 * designs: zero error df (unsorted runs, with covariation), a zero-df factor,
 * a zero error mean square, and the estimated variance of the mean when it
 * is negative. Hand check (C9): group sizes 1 and 3 with equal means, so
 * SS_a = 0, MSE = 1, C = (4 - 10/4) / 1 = 1.5, s2_a = -1/1.5 = -0.666667,
 * Var(mean) = -0.666667 * 10/16 + 1/4 = -1/6 < 0, printed as 0. Every case
 * logs "WARNING: The design is not balanced--F tests cannot be computed."
 * (BY groups add the BY-group NOTE), hence rc 1. Invented data (D-011). The
 * expected listing is a SAS 15.4 reference run of this program; the blank
 * line SAS writes before each new page title is dropped.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data c5; input a b y z @@; datalines;
1 1 3 1 1 2 5 2 1 1 4 4 2 1 8 3 2 2 6 5
;
title 'C5 zero error df, unsorted runs, covariation';
proc nested data=c5; class a b; var y z; run;
data c9; input a y @@; datalines;
1 5 2 4 2 5 2 6
;
title 'C9 negative estimated variance of the mean';
proc nested data=c9; class a; var y; run;
data c11; input a b y @@; datalines;
1 1 3 1 1 5 2 1 4 2 1 8 2 1 6
;
title 'C11 zero-df factor';
proc nested data=c11; class a b; var y; run;
data c12; input a b y @@; datalines;
1 1 3 1 1 3 1 2 5 2 1 4 2 1 4 2 2 9 2 2 9
;
title 'C12 zero error mean square';
proc nested data=c12; class a b; var y; run;
data d5; input g a y @@; datalines;
1 1 5 1 2 4 1 2 5 1 2 6 2 1 3 2 2 4 2 3 8
;
title 'D5 BY groups: negative variance of the mean, zero error df';
proc nested data=d5; by g; class a; var y; run;
