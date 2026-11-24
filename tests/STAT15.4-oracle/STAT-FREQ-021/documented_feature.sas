/* STAT-FREQ-021: FREQ — Official examples and feature integration regression
 * Source: S154 / Chapter 47 / `Examples: FREQ Procedure` (PDF pp. 3257–3283).
 * Discriminates: Example 47.10: Cochran's Q Test
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc format; value $ResponseFmt 'F'='Favorable' 'U'='Unfavorable'; run;
data drugs;
input Drug_A $ Drug_B $ Drug_C $ Count @@;
datalines;
F F F 6 U F F 2
F F U 16 U F U 4
F U F 2 U U F 6
F U U 4 U U U 6
;
proc freq data=Drugs;
tables Drug_A Drug_B Drug_C / nocum;
tables Drug_A*Drug_B*Drug_C / agree noprint;
format Drug_A Drug_B Drug_C $ResponseFmt.;
weight Count;
title 'Study of Three Drug Treatments for a Chronic Disease';
run;
