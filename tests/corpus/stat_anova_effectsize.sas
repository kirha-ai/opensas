/* STAT-ANOVA-003: MODEL / EFFECTSIZE (S154 p.1129; measures of GLM pp.4120-4122):
 * one-way, two-way with three responses of different scale, nested with INT
 * (intercept noncentrality above 1000), intercept-only, NOUNI, saturated (no
 * error DF), DFE 4 and 3 (Low MSE "."), tiny effect, zero error SS (Infty),
 * one-level effect, BY groups, per-BY-group unbalanced WARNING, and F up to
 * 6375. Invented data; tokens checked in order against SAS 9.4 runs of this
 * program (2026-11-28). */
options nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
data n; input A B C y x @@; z=y*1000+x*37; w=y/1000; datalines;
1 1 1 10 1 1 1 2 12 2 1 2 1 15 3 1 2 2 14 4 1 3 1 9 5 1 3 2 11 6
2 1 1 20 1 2 1 2 18 2 2 2 1 22 3 2 2 2 25 4 2 3 1 17 5 2 3 2 21 6
;
title 'e1 oneway';
proc anova data=n; class A; model y = A / effectsize; run;
title 'e2 twoway multi dep';
proc anova data=n; class A B; model y z w = A B / effectsize; run;
title 'e3 nested int';
proc anova data=n; class A B; model y = A B(A) / int effectsize; run;
title 'e4 intercept only';
proc anova data=n; class A; model y = / effectsize; run;
title 'e5 nouni';
proc anova data=n; class A; model y = A / nouni effectsize; run;
title 'e6 saturated';
proc anova data=n; class A B C; model y = A|B|C / effectsize; run;
title 'e7 small dfe';
proc anova data=n; class A B C; model y = A|B C / effectsize; run;
title 'e8 dfe 3';
proc anova data=n; class A B C; model y = A|B C A*C / effectsize; run;
title 'e9 tiny effect';
data t; input g y @@; datalines;
1 1 1 2 1 3 1 4 2 1.1 2 2.1 2 2.9 2 4 3 1 3 2 3 3.05 3 4
;
proc anova data=t; class g; model y = g / effectsize; run;
title 'e11 zero error';
data b; input blk t $ y @@; datalines;
1 A 1 1 B 2 2 A 3 2 C 5 3 B 4 3 C 8
;
proc anova data=b; class blk t; model y = blk t / effectsize; run;
title 'e12 one level';
data s; input g h y @@; datalines;
1 1 1 1 1 3 1 2 5 1 2 8 1 1 2 1 2 9 1 1 3 1 2 7
;
proc anova data=s; class g h; model y = g h / effectsize; run;
title 'e13 by';
data bb; input u A y @@; datalines;
1 1 3 1 1 4 1 1 5 1 2 8 1 2 9 1 2 11 1 1 4 1 2 10
2 1 1 2 1 4 2 1 2 2 2 3 2 2 5 2 2 4 2 1 3 2 2 6
;
proc anova data=bb; by u; class A; model y = A / effectsize; run;
title 'e14 by unbalanced warning';
data bu; input u A B y @@; datalines;
1 1 1 3 1 1 2 4 1 2 1 5 1 2 2 8 1 1 1 4
2 1 1 1 2 1 2 4 2 2 1 2 2 2 2 3
3 1 1 7 3 1 2 4 3 2 1 2 3 2 2 3 3 2 2 9
;
proc anova data=bu; by u; class A B; model y = A B; run;
title;
data h; do grp=1 to 3; sep=10**(grp/2);
 do g=1 to 3; do r=1 to 4; y = g*sep + mod(r*7+g*3,5)/2; output; end; end; end; run;
proc anova data=h; by grp; class g; model y = g / effectsize; run;
