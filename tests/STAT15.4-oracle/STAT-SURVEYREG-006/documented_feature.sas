/* STAT-SURVEYREG-006: SURVEYREG — Stratum Collapse / Sampling Rate of the Pooled Stratum from Collapse / Analysis of Variance (ANOVA)
 * Source: S154 / Chapter 123 / `Stratum Collapse` (PDF p. 10146); S154 / Chapter 123 / `Sampling Rate of the Pooled Stratum from Collapse` (PDF p. 10146); S154 / Chapter 123 / `Analysis of Variance (ANOVA)` (PDF pp. 10146–10147).
 * Discriminates: Example 123.6: Stratum Collapse
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Sample;
input Stratum X Y W;
datalines;
10 0 0 5
10 1 1 5
11 1 1 10
11 1 2 10
12 3 3 16
33 4 4 45
14 6 7 50
12 3 4 16
;
data StratumTotals;
input Stratum _TOTAL_;
datalines;
10 10
11 20
12 32
33 40
33 45
14 50
15 .
66 70
;
title1 'Stratified Sample with Single Sampling Unit in Strata';
title2 'With Stratum Collapse';
proc surveyreg data=Sample total=StratumTotals;
strata Stratum/list;
model Y=X;
weight W;
run;
title1 'Stratified Sample with Single Sampling Unit in Strata';
title2 'Without Stratum Collapse';
proc surveyreg data=Sample total=StratumTotals;
strata Stratum/list nocollapse;
model Y = X;
weight W;
run;
