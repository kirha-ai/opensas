/* STAT-LIFETEST-001: ID subj ($8): the ID value of each observation is listed beside its row.
 * Source: S154 / Chapter 77 / BY, FREQ, ID, STRATA, WEIGHT statements and Missing Values (PDF pp. 5662-5671).
 * Invented data. Expected output: SAS 9.4 / SAS/STAT 15.4 listing of this exact program
 * (batched reference run, 2026-11-28), not opensas output.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
title; footnote;
ods _all_ close;
ods listing;
ods graphics off;
data s2;
input site time status group $ n w subj $;
datalines;
1 1 1 A 1 1.5 s01
1 2 0 A 2 1 s02
1 2 1 A 1 2 s03
1 4 1 A 3 0.5 s04
1 5 0 A 1 1 s05
1 1 0 B 1 1 s06
1 3 1 B 2 1 s07
1 4 1 B 1 2.5 s08
1 6 0 B 1 1 s09
1 7 1 B 1 1 s10
2 1 1 A 1 1 s11
2 3 1 A 1 1 s12
2 6 0 A 1 1 s13
2 2 1 B 1 1 s14
2 5 1 B 1 1 s15
2 8 0 B 1 1 s16
;
run;
proc lifetest data=s2(where=(site=1));
time time*status(0);
strata group;
id subj;
run;
