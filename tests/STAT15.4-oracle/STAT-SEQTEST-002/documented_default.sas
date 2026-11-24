/* STAT-SEQTEST-002: SEQTEST — Stage updates and inference for group sequential tests
 * Source: S154 / Chapter 111 / `Getting Started: SEQTEST Procedure` (PDF pp. 9143–9156); S154 / Chapter 111 / `Overview: SEQTEST Procedure` (PDF pp. 9138–9143).
 * Discriminates: Small synthetic/public-input default model adapted to the documented Getting Started procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc seqdesign altref=-10; TwoSided: design nstages=4 method=obf; samplesize model=twosamplemean(stddev=20); ods output Boundary=boundaries; run;
data estimates; length Variable $8 _Scale_ $8; Variable='Trt'; _Scale_='MLE'; _Stage_=1; Estimate=-7; StdErr=4.5; run;
proc seqtest boundary=boundaries parms(testvar=Trt)=estimates infoadj=prop; run;
