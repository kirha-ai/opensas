/* STAT-GLMPOWER-007: GLMPOWER — REPEATED
 * Source: S154 / Chapter 55 / `REPEATED Statement` (PDF pp. 4277–4280).
 * Discriminates: Example 55.3: Repeated Measures ANOVA; explicit statements: REPEATED
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Pain;
input Treatment $ PainMem0 PainMem1Wk PainMem6Mo PainMem12Mo;
datalines;
SensoryFocus 2.40 2.38 2.05 1.90
StandardOfCare 2.40 2.39 2.36 2.30
;
ods graphics on;
proc glmpower data=Pain;
class Treatment;
model PainMem0 PainMem1Wk PainMem6Mo PainMem12Mo = Treatment;
repeated Time contrast;
power
mtest = hlt
alpha = 0.01
power = .9
ntotal = .
stddev = 0.92 1.04
matrix ("PainCorr") = lear(0.6, 0.8, 4, 0 1 26 52)
corrmat = "PainCorr";
plot y=power min=0.05 max=0.99 yopts=(ref=0.9)
vary (linestyle by stddev, symbol by dependent source);
run;
ods graphics off;
run;
quit;
