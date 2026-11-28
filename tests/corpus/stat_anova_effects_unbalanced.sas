/* STAT-ANOVA-003: unbalanced one-way (no warning) and two-way models with two
 * responses (one WARNING per step, SS from cell totals); numeric REF= level and
 * global REF=FIRST with a per-variable override. Invented data; tokens checked
 * in order against SAS 9.4 runs of this program (2026-11-28); last two steps:
 * one-level CLASS effects (DF 0, `.` tests). */
options nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
data s; input g y z @@; datalines;
2 5 1 1 1 2 2 7 4 1 3 3 2 9 9
;
title 's1 oneway unbalanced';
proc anova data=s; class g; model y z = g; run;
data n; input A B y @@; datalines;
1 1 10 1 1 12 1 2 15 1 2 14 1 3 9 1 3 11
2 1 20 2 1 18 2 2 22 2 2 25 2 3 17 2 3 21
1 1 13
;
title 's2 twoway unbalanced two responses';
data n2; set n; z=y*2; run;
proc anova data=n2; class A B; model y z = A B; run;
title 's3 class ref numeric value';
proc anova data=n; class B(ref='2'); model y=B; run;
title 's4 ref global first and var last';
proc anova data=n; class A(ref=last) B / ref=first; model y=A B; run;
data s; input g h y @@; datalines;
1 1 1 1 1 3 1 2 5 1 2 8
;
title 'w1 one level';
proc anova data=s; class g; model y=g; run;
title 'w2 one level with other';
proc anova data=s; class g h; model y=g h; run;
