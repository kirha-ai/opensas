/* STAT-LIFETEST-005: LIFETEST — Analysis of Competing-Risks Data
 * Source: S154 / Chapter 77 / `Analysis of Competing-Risks Data` (PDF pp. 5687–5690).
 * Discriminates: Cumulative incidence with a censoring code, two failure causes, and two strata.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data survival;
input time status group $;
datalines;
1 1 A
2 0 A
3 2 A
4 1 A
5 0 A
7 1 A
1 2 B
2 1 B
3 0 B
4 2 B
6 1 B
8 0 B
;
run;
proc lifetest data=survival timelist=1 2 4 6;
time time*status(0) / eventcode=1;
strata group;
run;
