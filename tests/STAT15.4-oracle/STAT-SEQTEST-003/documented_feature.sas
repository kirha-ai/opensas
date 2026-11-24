/* STAT-SEQTEST-003: SEQTEST — Boundary Variables / Information Level Adjustments at Future Stages / Boundary Adjustments for Information Levels
 * Source: S154 / Chapter 111 / `Boundary Variables` (PDF pp. 9169–9172); S154 / Chapter 111 / `Information Level Adjustments at Future Stages` (PDF pp. 9172–9173); S154 / Chapter 111 / `Boundary Adjustments for Information Levels` (PDF pp. 9173–9175).
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
