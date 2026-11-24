/* STAT-SIMNORMAL-004: SIMNORMAL — Conditional Simulation
 * Source: S154 / Chapter 113 / `Conditional Simulation` (PDF pp. 9372–9373).
 * Discriminates: Verified default procedure context
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data scov(type=cov);
length _name_ $32 _type_ $8;
infile datalines truncover;

length _TYPE_ $8 _NAME_ $8;
input _TYPE_ $ _NAME_ $ s1 s2;
datalines;
COV s1 1.915 0.3873
COV s2 0.3873 4.321
MEAN . 1.305 2.003
;
run;
proc simnorm data=scov outsim=draws numreal=500 seed=54321;
var s1 s2;
run;
proc corr data=draws cov;
var s1 s2;
run;
