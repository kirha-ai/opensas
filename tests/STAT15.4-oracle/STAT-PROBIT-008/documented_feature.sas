/* STAT-PROBIT-008: PROBIT — LSMEANS / LSMESTIMATE / SLICE
 * Source: S154 / Chapter 100 / `LSMEANS Statement` (PDF pp. 8110–8111); S154 / Chapter 100 / `LSMESTIMATE Statement` (PDF pp. 8111–8112); S154 / Chapter 100 / `SLICE Statement` (PDF p. 8119).
 * Discriminates: Example 100.5: Model Postfitting Analysis; explicit statements: SLICE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data epidemic;
input treat$ dose n r sex @@;
label dose = Dose;
datalines;
A 2.17 142 142 0 A .57 132 47 1 A 1.68 128 105 1 A 1.08 126 100 0
A 1.79 125 118 0 B 1.66 117 115 1 B 1.49 127 114 0 B 1.17 51 44 1
B 2.00 127 126 0 B .80 129 100 1
;
run;
proc probit data=epidemic;
class treat sex;
model r/n = dose treat sex treat*sex;
slice treat*sex / diff;
effectplot;
run;
