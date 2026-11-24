/* STAT-CATMOD-009: CATMOD — REPEATED / Repeated Measures Analysis
 * Source: S154 / Chapter 36 / `REPEATED Statement` (PDF pp. 2211–2212); S154 / Chapter 36 / `Repeated Measures Analysis` (PDF pp. 2232–2234).
 * Discriminates: Example 36.6: Repeated Measures, 2 Response Levels, 3 Populations; explicit statements: REPEATED
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data group;
input a b c d Group wt @@;
datalines;
1 1 1 1 2 2 0 0 0 0 2 2 0 0 1 0 1 2 0 0 1 0 2 2
0 0 0 1 1 4 0 0 0 1 2 1 0 0 0 1 3 3 1 0 0 1 2 1
0 0 1 1 1 1 0 0 1 1 2 2 0 0 1 1 3 5 0 1 0 0 1 4
0 1 0 0 2 1 0 1 0 1 2 1 0 1 0 1 3 2 0 1 1 0 3 1
1 0 0 0 1 3 1 0 0 0 2 1 0 1 1 1 2 1 0 1 1 1 3 2
1 0 1 0 1 1 1 0 1 1 2 1 1 0 1 1 3 2
;
title 'Multiple-Population Repeated Measures';
proc catmod data=group;
weight wt;
response marginals;
model a*b*c*d=Group _response_ Group*_response_
/ freq;
repeated Trial 4;
title2 'Saturated Model';
run;
model a*b*c*d=Group _response_(Group=3)
/ noprofile noparm design;
title2 'Trial Nested within Group 3';
quit;
