/* STAT-RSREG-009: RSREG — Official examples and feature integration regression
 * Source: S154 / Chapter 108 / `Examples: RSREG Procedure` (PDF pp. 8891–8900).
 * Discriminates: Example 108.1: A Saddle Surface Response Using Ridge Analysis
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data d;
input Time Temp MBT;
label Time = "Reaction Time (Hours)"
Temp = "Temperature (Degrees Centigrade)"
MBT = "Percent Yield Mercaptobenzothiazole";
datalines;
4.0 250 83.8
20.0 250 81.7
12.0 250 82.4
12.0 250 82.9
12.0 220 84.7
12.0 280 57.9
12.0 250 81.2
6.3 229 81.3
6.3 271 83.1
17.7 229 85.3
17.7 271 72.7
4.0 250 82.0
;
ods graphics on;
proc rsreg data=d plots=(ridge surface);
model MBT=Time Temp / lackfit;
ridge max;
run;
ods graphics off;
run;
quit;
