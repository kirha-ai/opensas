/* STAT-LIFETEST-001: two strata whose largest has 12 observations: every product-limit table uses the 10-99 Number column layout.
 * Source: S154 / Chapter 77 / PROC LIFETEST and STRATA statements (PDF pp. 5650-5668).
 * Invented data. Expected output: SAS 9.4 / SAS/STAT 15.4 listing of this exact program
 * (batched reference run, 2026-11-28), not opensas output.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
title; footnote;
ods _all_ close;
ods listing;
ods graphics off;
data s6;
input time status group $ @@;
datalines;
1 1 A 1 0 A 2 1 A 2 0 A 3 1 A 3 0 A 4 1 A 4 0 A 5 1 A 6 0 A 7 1 A 8 0 A
1 0 B 3 1 B 5 1 B 9 0 B
;
run;
proc lifetest data=s6;
time time*status(0);
strata group;
run;
