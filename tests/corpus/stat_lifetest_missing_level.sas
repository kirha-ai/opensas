/* STAT-LIFETEST-001: MISSING with a blank STRATA value: the missing level is valid, listed blank and ordered first; levels ascend although the data are not sorted; three strata (2 DF tests, 3x3 covariances).
 * Source: S154 / Chapter 77 / BY, FREQ, ID, STRATA, WEIGHT statements and Missing Values (PDF pp. 5662-5671).
 * Invented data. Expected output: SAS 9.4 / SAS/STAT 15.4 listing of this exact program
 * (batched reference run, 2026-11-28), not opensas output.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
title; footnote;
ods _all_ close;
ods listing;
ods graphics off;
data s3;
input time status group $;
datalines;
1 0 B
3 1 B
4 1 B
7 1 B
1 1 A
2 1 A
4 1 A
5 0 A
2 1 .
3 0 .
6 1 .
;
run;
proc lifetest data=s3 missing;
time time*status(0);
strata group;
run;
