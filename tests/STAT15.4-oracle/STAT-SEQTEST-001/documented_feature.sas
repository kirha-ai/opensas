/* STAT-SEQTEST-001: SEQTEST — Data input, variable roles, and basic options
 * Source: S154 / Chapter 111 / `PROC SEQTEST Statement` (PDF pp. 9156–9167); S154 / Chapter 111 / `Input Data Sets` (PDF pp. 9167–9169).
 * Discriminates: Verified default procedure context
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc seqdesign altref=-10;
TwoSided: design nstages=4 method=obf;
samplesize model=twosamplemean(stddev=20);
ods output Boundary=boundaries;
run;
data estimates;
length Variable $8 _Scale_ $8;
Variable='Trt';
_Scale_='MLE';
_Stage_=1;
Estimate=-7;
StdErr=4.5;
run;
proc seqtest boundary=boundaries parms(testvar=Trt)=estimates infoadj=prop;
run;
