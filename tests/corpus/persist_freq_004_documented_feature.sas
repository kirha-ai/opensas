/* STAT-FREQ-004: FREQ — EXACT / Exact Statistics
 * Source: S154 / Chapter 47 / `EXACT Statement` (PDF pp. 3085–3094); S154 / Chapter 47 / `Exact Statistics` (PDF pp. 3234–3238).
 * Discriminates: Example 47.5: Analysis of a 2x2 Contingency Table; explicit statements: EXACT
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc format; value ExpFmt 1='High Cholesterol Diet' 0='Low Cholesterol Diet'; value RspFmt 1='Yes' 0='No'; run;
data FatComp;
input Exposure Response Count;
label Response='Heart Disease';
datalines;
0 0 6
0 1 2
1 0 4
1 1 11
;
proc sort data=FatComp;
by descending Exposure descending Response;
run;
proc freq data=FatComp order=data;
format Exposure ExpFmt. Response RspFmt.;
tables Exposure*Response / chisq relrisk;
exact pchi or;
weight Count;
title 'Case-Control Study of High Fat/Cholesterol Diet';
run;
