/* STAT-ANOVA-003: MEANS after REF=, NOUNI with MEANS, repeated/self-nested
 * effects, incomplete blocks (Model capped at the corrected total), INT with
 * nesting, character REF=, INTERCEPT, nested bar operands, saturated three-way,
 * CLASS-missing rows dropped. Invented data; tokens checked in order against a
 * SAS 9.4 run of this program (2026-11-28). */
options nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
data n; input A B C y x @@; datalines;
1 1 1 10 1 1 1 2 12 2 1 2 1 15 3 1 2 2 14 4 1 3 1 9 5 1 3 2 11 6
2 1 1 20 1 2 1 2 18 2 2 2 1 22 3 2 2 2 25 4 2 3 1 17 5 2 3 2 21 6
;
title 'r1 means ref';
proc anova data=n; class A B(ref=first); model y = A B; means B; run;
title 'r2 means nouni';
proc anova data=n; class B; model y = B / nouni; means B; run;
title 'r3 dup';
proc anova data=n; class A; model y = A A; run;
title 'r4 AA';
proc anova data=n; class A; model y = A*A; run;
title 'r5 A(A)';
proc anova data=n; class A; model y = A(A); run;
title 'r6 bibd';
data b; input blk t $ y @@; datalines;
1 A 1 1 B 2 2 A 3 2 C 5 3 B 4 3 C 8
;
proc anova data=b; class blk t; model y = blk t; run;
title 'r7 int nested';
proc anova data=n; class A B; model y = A B(A) / int; run;
title 'r8 char ref';
data c; set n; length g $2; g=ifc(B=1,'lo',ifc(B=2,'mi','hi')); run;
proc anova data=c; class g(ref='mi'); model y = g; run;
title 'r9 ref last per var';
proc anova data=c; class g(ref=last) A(ref=first); model y = g A; run;
title 'r10 int option name';
proc anova data=n; class A; model y = A / intercept; run;
title 'r12 nested bar';
proc anova data=n; class A B C; model y = A(B) | C(B); run;
title 'r13 three-way equal';
proc anova data=n; class A B C; model y = A|B|C; run;
title 'r14 missing class rows dropped';
data m2; set n end=e; output; if e then do; A=.; y=99; output; A=1; B=.; y=98; output; end; run;
proc anova data=m2; class A B; model y = A B(A); run;
