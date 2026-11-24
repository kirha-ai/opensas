/* STAT-SEQTEST-007: SEQTEST — Table Output / ODS Table Names
 * Source: S154 / Chapter 111 / `Table Output` (PDF pp. 9184–9188); S154 / Chapter 111 / `ODS Table Names` (PDF p. 9188).
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

ods trace on;
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
ods trace off;
