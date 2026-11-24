/* STAT-LIFETEST-002: LIFETEST — Nonparametric survival distributions and group comparisons
 * Source: S154 / Chapter 77 / `Getting Started: LIFETEST Procedure` (PDF pp. 5641–5649); S154 / Chapter 77 / `Overview: LIFETEST Procedure` (PDF pp. 5640–5641).
 * Discriminates: Documented default analysis with explicit complete public or synthetic inputs
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data survival; input time status group $; datalines;
1 1 A
2 0 A
2 1 A
4 1 A
5 0 A
1 0 B
3 1 B
4 1 B
6 0 B
7 1 B
;
run;
proc lifetest data=survival; time time*status(0); strata group; run;
