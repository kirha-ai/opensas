/* STAT-COMMON-015: Survival data and censoring contracts
 * Source: S154 / Chapter 14 / `Introduction to Survival Analysis Procedures` (PDF pp. 255–262).
 * Discriminates: Event/censoring ties, stratum boundaries and survival result contract
 * Invented data. The expected listing is the SAS reference output for this
 * program: NOTABLE leaves the censoring summary and the homogeneity tests.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data survival; input time status group $ x; datalines;
1 1 A 1
2 0 A 2
2 1 A 3
4 1 A 2
5 0 A 4
1 0 B 1
3 1 B 2
4 1 B 4
6 0 B 3
7 1 B 5
;
run;
proc lifetest data=survival notable; time time*status(0); strata group; run;
