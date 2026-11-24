/* STAT-FREQ-007: FREQ — Binomial Proportion
 * Source: S154 / Chapter 47 / `Binomial Proportion` (PDF pp. 3180–3188).
 * Discriminates: Example 47.4: Binomial Proportions
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Color;
input Region Eyes $ Hair $ Count @@;
label Eyes ='Eye Color'
Hair ='Hair Color'
Region='Geographic Region';
datalines;
1 blue fair 23 1 blue red 7 1 blue medium 24
1 blue dark 11 1 green fair 19 1 green red 7
1 green medium 18 1 green dark 14 1 brown fair 34
1 brown red 5 1 brown medium 41 1 brown dark 40
1 brown black 3 2 blue fair 46 2 blue red 21
2 blue medium 44 2 blue dark 40 2 blue black 6
2 green fair 50 2 green red 31 2 green medium 37
2 green dark 23 2 brown fair 56 2 brown red 42
2 brown medium 53 2 brown dark 54 2 brown black 13
;
run;
proc freq data=Color order=freq;
tables Eyes / binomial(ac wilson exact) alpha=.1;
tables Hair / binomial(equiv p=.28 margin=.1);
weight Count;
title 'Hair and Eye Color of European Children';
run;
