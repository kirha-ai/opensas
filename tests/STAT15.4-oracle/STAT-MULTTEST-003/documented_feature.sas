/* STAT-MULTTEST-003: MULTTEST — Statistical Tests / p-Value Adjustments
 * Source: S154 / Chapter 86 / `Statistical Tests` (PDF pp. 6914–6922); S154 / Chapter 86 / `p-Value Adjustments` (PDF pp. 6922–6930).
 * Discriminates: Getting Started: MULTTEST Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Drug;
input Dose$ SideEff1-SideEff10;
datalines;
0MG 0 0 1 0 0 1 0 0 0 0
0MG 0 0 0 0 0 0 0 0 0 1
0MG 0 0 0 0 0 0 0 0 1 0
0MG 0 0 0 0 0 0 0 0 0 0
0MG 0 1 0 0 0 0 0 0 0 0
1MG 1 0 0 1 0 1 0 0 1 0
1MG 0 0 0 1 1 0 0 1 0 1
1MG 0 1 0 0 0 0 1 0 0 0
1MG 0 0 1 0 0 0 0 0 0 1
1MG 1 0 1 0 0 0 0 1 0 0
2MG 0 1 1 1 0 1 1 1 0 1
2MG 1 1 1 1 1 1 0 1 1 0
2MG 1 0 0 1 0 1 1 0 1 0
2MG 0 1 1 1 1 0 1 1 1 1
2MG 1 0 1 0 1 1 1 0 0 1
;
ods graphics on;
proc multtest bootstrap nsample=499 seed=41287 notables
plots=PByTest(vref=0.05 0.1);
class Dose;
test ca(SideEff1-SideEff10);
contrast 'Trend' 0 1 2;
run;
ods graphics off;
run;
quit;
