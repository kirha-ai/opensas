/* STAT-PLM-003: PLM — FILTER / SHOW / WHERE
 * Source: S154 / Chapter 94 / `FILTER Statement` (PDF pp. 7635–7636); S154 / Chapter 94 / `SHOW Statement` (PDF pp. 7641–7643); S154 / Chapter 94 / `WHERE Statement` (PDF pp. 7644–7646).
 * Discriminates: Getting Started: PLM Procedure; explicit statements: SHOW
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data BlockDesign;
input block a b y @@;
datalines;
1 1 1 56 1 1 2 41
1 2 1 50 1 2 2 36
1 3 1 39 1 3 2 35
2 1 1 30 2 1 2 25
2 2 1 36 2 2 2 28
2 3 1 33 2 3 2 30
3 1 1 32 3 1 2 24
3 2 1 31 3 2 2 27
3 3 1 15 3 3 2 19
4 1 1 30 4 1 2 25
4 2 1 35 4 2 2 30
4 3 1 17 4 3 2 18
;
proc glm data=BlockDesign;
class block a b;
model y = block a b a*b / solution;
store work.BlockAnalysis / label='PLM: Getting Started';
run;
proc plm restore=work.BlockAnalysis;
run;
proc plm restore=work.BlockAnalysis;
show fit parms;
test a b a*b;
run;
proc plm restore=work.BlockAnalysis seed=3;
lsmeans a / diff;
lsmestimate a -1 1,
1 1 -2 / uppertailed ftest;
run;
ods graphics on;
proc plm restore=work.BlockAnalysis;
slice a*b / sliceby(b='1') diff;
run;
ods graphics off;
run;
quit;
