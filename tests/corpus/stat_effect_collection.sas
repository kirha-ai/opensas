/* STAT-COMMON-021: EFFECT name=COLLECTION(x z) in PROC GLMSELECT with
 * SELECTION=NONE: one effect with two degrees of freedom (Dimensions 2/3),
 * the one-step Least Squares Summary, the full-model ANOVA, fit statistics
 * and parameter rows labelled "both x" / "both z". Expected listing is the
 * SAS/STAT 15.4 reference listing of this program (invented data).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data sample;
 input x z y group $ weight freq;
 datalines;
1 1 4 A 1 1
2 1 6 A 2 1
3 2 7 A 1 2
4 1 9 A 1 1
5 3 13 A 2 1
6 2 12 A 1 1
7 4 17 B 1 1
8 3 19 B 2 2
9 5 20 B 1 1
10 3 23 B 1 1
11 5 25 B 2 1
12 4 24 B 1 1
;
run;
proc glmselect data=sample seed=314159; effect both=collection(x z); model y=both / selection=none; run;
