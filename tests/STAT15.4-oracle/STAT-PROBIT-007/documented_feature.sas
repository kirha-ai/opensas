/* STAT-PROBIT-007: PROBIT — ESTIMATE / TEST / Inverse Confidence Limits
 * Source: S154 / Chapter 100 / `ESTIMATE Statement` (PDF pp. 8109–8110); S154 / Chapter 100 / `TEST Statement` (PDF p. 8120); S154 / Chapter 100 / `Inverse Confidence Limits` (PDF pp. 8127–8128).
 * Discriminates: Example 100.4: An Epidemiology Study; explicit statements: TEST
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
data xval;
input treat $ dose sex;
datalines;
B 2. 1
;
ods graphics on;
proc probit optc lackfit covout data=epidemic
outest = out1 xdata = xval
Plots=(predpplot ippplot lpredplot);
class treat sex;
model r/n = dose treat sex sex*treat/corrb covb inversecl;
estimate 'Dose coefficient' dose 1;
test dose;
output out = out2 p =p;
run;

ods graphics off;
