/* STAT-LIFETEST-001: no STRATA statement, 10 observations: one estimates page, one-sample censoring summary, no tests; Number columns one place right for 10-99 observations.
 * Source: S154 / Chapter 77 / PROC LIFETEST and STRATA statements (PDF pp. 5650-5668).
 * Invented data. Expected output: SAS 9.4 / SAS/STAT 15.4 listing of this exact program
 * (batched reference run, 2026-11-28), not opensas output.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
title; footnote;
ods _all_ close;
ods listing;
ods graphics off;
data s4;
input time status grp sex $;
datalines;
1 1 1 F
2 0 1 M
2 1 1 F
4 1 1 M
5 0 1 F
1 0 2 M
3 1 2 F
4 1 2 M
6 0 2 F
7 1 2 M
;
run;
proc lifetest data=s4;
time time*status(0);
run;
