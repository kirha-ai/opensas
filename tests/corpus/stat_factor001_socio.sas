/* STAT-FACTOR-001: PROC FACTOR default METHOD=PRINCIPAL PRIORS=ONE analysis
 * with SIMPLE, CORR, N=5 SCORE and two identical BY groups. Data: the
 * published socioeconomics sample of the SAS/STAT FACTOR chapter. Expected
 * listing taken from the SAS 9.4 / SAS/STAT 15.4 reference listing (BY variable
 * renamed grp), not from opensas output.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
ods graphics off;
data SocioEconomics;
input Population School Employment Services HouseValue;
datalines;
5700 12.8 2500 270 25000
1000 10.9 600 10 10000
3400 8.8 1000 10 9000
3800 13.6 1700 140 25000
4000 12.8 1600 140 25000
8200 8.3 2600 60 12000
1200 11.4 400 10 16000
9100 11.5 3300 60 14000
9900 12.5 3400 180 18000
9600 13.7 3600 390 25000
9600 9.6 3300 80 12000
9400 11.4 4000 100 13000
;
proc factor data=SocioEconomics simple corr;
run;
proc factor data=SocioEconomics n=5 score;
run;
data byinput; set SocioEconomics; do grp=1 to 2; output; end; run;
proc sort data=byinput; by grp; run;
proc factor data=byinput simple corr;
by grp;
run;
