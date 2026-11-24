/* STAT-MULTTEST-004: MULTTEST — CONTRAST / TEST
 * Source: S154 / Chapter 86 / `CONTRAST Statement` (PDF pp. 6910–6911); S154 / Chapter 86 / `TEST Statement` (PDF pp. 6912–6914).
 * Discriminates: Getting Started: MULTTEST Procedure; explicit statements: CONTRAST, TEST
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
