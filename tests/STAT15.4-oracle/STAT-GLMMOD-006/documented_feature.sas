/* STAT-GLMMOD-006: GLMMOD — Official examples and feature integration regression
 * Source: S154 / Chapter 54 / `Examples: GLMMOD Procedure` (PDF pp. 4242–4250).
 * Discriminates: Example 54.1: A Two-Way Design
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Plants;
input Type $ @;
do Block=1 to 3;
input StemLength @;
output;
end;
datalines;
Clarion 32.7 32.3 31.5
Clinton 32.1 29.7 29.1
Knox 35.7 35.9 33.1
O'Neill 36.0 34.2 31.2
Compost 31.8 28.0 29.2
Wabash 38.2 37.8 31.9
Webster 32.5 31.1 29.7
;
proc glmmod data=Plants outparm=Parm outdesign=Design;
class Type Block;
model StemLength = Type|Block;
run;
proc print data=Parm;
run;
proc print data=Design;
run;
