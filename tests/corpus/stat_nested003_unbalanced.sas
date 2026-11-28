/* expect-rc: 1
 * STAT-NESTED-003: Unbalanced Data and the General Random-Effects Model: two- and three-factor unbalanced designs (EMS coefficients with 8 decimals, blank F-test columns, back-substituted variance components incl. negative ones with 0 percent, SE of the mean from the signed components), the analysis of covariation for an unbalanced pair, y with itself, and a one-factor design. Values also match an independent quadratic-form trace calculation.
 * Invented data (D-011). The expected listing is a SAS 15.4 reference run of
 * this program (every case logs "WARNING: The design is not balanced--F tests
 * cannot be computed.", hence rc 1 as SAS); the blank line SAS writes before
 * each new page title is dropped (opensas starts pages without it).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
data u2;
input A B y z @@;
datalines;
1 1 3 1  1 1 5 2  1 2 4 4  1 2 6 3  1 2 8 7
2 1 7 5  2 1 9 6  2 1 8 8  2 2 2 1
3 1 6 2  3 1 4 5  3 2 5 5  3 2 7 4  3 3 9 9  3 3 6 3
;
title 'C1 unbalanced two-factor';
proc nested data=u2; class A B; var y; run;
title 'C2 covariation unbalanced two vars';
proc nested data=u2; class A B; var y z; run;
data u3;
input P Q R y @@;
datalines;
1 1 1 10 1 1 1 12 1 1 2 11 1 2 1 14 1 2 1 15 1 2 1 13
2 1 1 20 2 1 1 18 2 1 2 19 2 1 2 22 2 2 1 17 2 3 1 16 2 3 1 21
;
title 'C3 unbalanced three-factor';
proc nested data=u3; class P Q R; var y; run;
data auto;
input Make $ Model Score @@;
S2 = mod(Score*7, 11) + Score/2;
S3 = mod(Score, 5);
datalines;
a 1 62 a 2 77 a 3 59 a 1 67 a 2 73 a 3 64 a 1 60 a 2 79 a 3 60
b 1 72 b 2 58 b 3 80 b 1 75 b 2 63 b 3 84 b 1 69 b 2 57 b 3 89
c 1 94 c 2 76 c 3 81 c 1 90 c 2 75 c 3 85 c 1 88 c 2 78 c 3 85
d 1 69 d 2 73 d 3 90 d 1 72 d 2 88 d 3 87 d 1 76 d 2 87 d 3 92
;
data neg;
input A B y @@;
datalines;
1 1 5 1 1 6 1 2 5 1 2 6 1 2 5
2 1 5 2 1 6 2 2 6 2 2 5
3 1 6 3 1 5 3 1 5
;
title 'C6 unbalanced negative component';
proc nested data=neg; class A B; var y; run;
title 'C7 y with y';
proc nested data=u2; class A B; var y y; run;
title 'C8 one factor unbalanced';
proc nested data=u2; class A; var y z; run;
