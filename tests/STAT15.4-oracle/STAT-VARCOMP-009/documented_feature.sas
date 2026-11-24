/* STAT-VARCOMP-009: VARCOMP — Official examples and feature integration regression
 * Source: S154 / Chapter 130 / `Examples: VARCOMP Procedure` (PDF pp. 10742–10749).
 * Discriminates: Example 130.1: Using the Four General Estimation Methods
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data a;
input a b y @@;
datalines;
1 1 237 1 1 254 1 1 246 1 2 178 1 2 179
2 1 208 2 1 178 2 1 187 2 2 146 2 2 145 2 2 141
3 1 186 3 1 183 3 2 142 3 2 125 3 2 136
;
proc varcomp method=type1 data=a;
class a b;
model y=a|b / fixed=1;
run;
proc varcomp method=mivque0 data=a;
class a b;
model y=a|b / fixed=1;
run;
proc varcomp method=ml data=a;
class a b;
model y=a|b / fixed=1;
run;
proc varcomp method=reml data=a;
class a b;
model y=a|b / fixed=1;
run;
