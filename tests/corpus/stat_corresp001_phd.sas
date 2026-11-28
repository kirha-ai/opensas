/* STAT-CORRESP-001: PROC CORRESP with VAR-statement input and an ID
 * variable on the chapter's published Ph.D. table (S154 ch.41), ODS Graphics
 * off: the default listing (inertia and chi-square decomposition, row and
 * column coordinates and every point statistic) and SHORT CHI2P with
 * three-letter aliases. Expected listing: SAS 9.4 (SAS/STAT 15.4) output.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data PhD;
input Science $ 1-19 y1973-y1978;
label y1973 = '1973' y1974 = '1974' y1975 = '1975' y1976 = '1976' y1977 = '1977' y1978 = '1978';
datalines;
Life Sciences       4489 4303 4402 4350 4266 4361
Physical Sciences   4101 3800 3749 3572 3410 3234
Social Sciences     3354 3286 3344 3278 3137 3008
Behavioral Sciences 2444 2587 2749 2878 2960 3049
Engineering         3338 3144 2959 2791 2641 2432
Mathematics         1222 1196 1149 1003 959 959
;
ods graphics off;
title "A";
proc corresp data=PhD outc=R1;
var y1973-y1978;
id Science;
run;
title "B";
proc corresp dat=PhD sho chi;
var y1973-y1978;
id Science;
run;
