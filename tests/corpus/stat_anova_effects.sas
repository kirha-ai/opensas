/* STAT-ANOVA-003: PROC ANOVA effect specification (S154 pp.1123-1126 printed,
 * physical 1135-1138): nested, pooled, order-independent, bar/@, crossed-nested,
 * intercept-only, INT, NOUNI, REF=, TRUNCATE, Latin square, unbalanced cells.
 * Invented data; every printed token checked in order against a SAS 9.4 run of
 * this program (2026-11-28). */
options nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
data n; input A B C y x @@; datalines;
1 1 1 10 1 1 1 2 12 2 1 2 1 15 3 1 2 2 14 4 1 3 1 9 5 1 3 2 11 6
2 1 1 20 1 2 1 2 18 2 2 2 1 22 3 2 2 2 25 4 2 3 1 17 5 2 3 2 21 6
;
title 'q1 nested';
proc anova data=n; class A B; model y = A B(A); run;
title 'q2 pooled';
proc anova data=n; class A B; model y = A A*B; run;
title 'q3 order';
proc anova data=n; class A B; model y = A*B A B; run;
title 'q4 bar at';
proc anova data=n; class A B C; model y = A|B|C@2; run;
title 'q5 bar nested';
proc anova data=n; class A B C; model y = A|B(A)|C; run;
title 'q6 intercept only';
proc anova data=n; class A; model y = ; run;
title 'q7 int';
proc anova data=n; class A B; model y = A B / int; run;
title 'q8 nouni';
proc anova data=n; class A; model y = A / nouni; run;
title 'q9 ref';
proc anova data=n; class A(ref='1') B / ref=first; model y = A B; run;
title 'q11 missing level';
data m; set n; if _n_=3 then B=.; run;
proc anova data=m; class A B; model y = A B; run;
title 'q14 nested only';
proc anova data=n; class A B; model y = B(A); run;
title 'q15 crossed nested';
proc anova data=n; class A B C; model y = A B(A) C*B(A); run;
data t; length L $20; input L $ y @@; datalines;
abcdefghijklmnopqX 1 abcdefghijklmnopqY 2 abcdefghijklmnopqX 3 abcdefghijklmnopqY 5 zz 7 zz 8
;
title 'q16 truncate';
proc anova data=t; class L / truncate; model y = L; run;
title 'q17 no truncate';
proc anova data=t; class L; model y = L; run;
title 'q18 ref first global B';
proc anova data=n; class B / ref=last; model y = B; run;
title 'q20 latin';
data l; input r c t $ y @@; datalines;
1 1 A 5 1 2 B 7 1 3 C 6 2 1 B 8 2 2 C 9 2 3 A 4 3 1 C 6 3 2 A 3 3 3 B 9
;
proc anova data=l; class r c t; model y = r c t; run;
title 'q22 unbalanced';
data u; set n; if _n_ in (1,2) then delete; run;
proc anova data=u; class A B; model y = A B A*B; run;
