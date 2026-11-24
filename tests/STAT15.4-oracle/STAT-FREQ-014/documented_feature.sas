/* STAT-FREQ-014: FREQ — Cochran-Mantel-Haenszel Statistics
 * Source: S154 / Chapter 47 / `Cochran-Mantel-Haenszel Statistics` (PDF pp. 3223–3233).
 * Discriminates: Example 47.7: Cochran-Mantel-Haenszel Statistics
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Migraine;
input Gender $ Treatment $ Response $ Count @@;
datalines;
female Active Better 16 female Active Same 11
female Placebo Better 5 female Placebo Same 20
male Active Better 12 male Active Same 16
male Placebo Better 7 male Placebo Same 19
;
ods graphics on;
proc freq data=Migraine;
tables Gender*Treatment*Response /
relrisk plots(only)=relriskplot(stats) cmh noprint;
weight Count;
title 'Clinical Trial for Treatment of Migraine Headaches';
run;
ods graphics off;
run;
quit;
