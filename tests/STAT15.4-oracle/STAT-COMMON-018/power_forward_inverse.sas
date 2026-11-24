/* STAT-COMMON-018: Power and sample size inversion interface
 * Source: S154 / Chapter 19 / `Computing Power and Sample Size` (PDF pp. 395–396); S154 / Chapter 19 / `Hypothesis Testing, Power, and Confidence Interval Precision` (PDF pp. 394–395).
 * Discriminates: Forward power versus sample size inversion and executable sample size rounding
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc power;
 twosamplemeans test=diff meandiff=2 stddev=3 alpha=0.05 power=0.8 ntotal=.;
 twosamplemeans test=diff meandiff=2 stddev=3 alpha=0.05 power=. ntotal=100;
run;
