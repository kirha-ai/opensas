/* STAT-LIFETEST-001: no STRATA statement, 5 observations: reference Number column layout.
 * Source: S154 / Chapter 77 / PROC LIFETEST and STRATA statements (PDF pp. 5650-5668).
 * Invented data. Expected output: SAS 9.4 / SAS/STAT 15.4 listing of this exact program
 * (batched reference run, 2026-11-28), not opensas output.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
title; footnote;
ods _all_ close;
ods listing;
ods graphics off;
data s5;
input time status;
datalines;
1 1
2 0
2 1
4 1
5 0
;
run;
proc lifetest data=s5;
time time*status(0);
run;
