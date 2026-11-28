/* STAT-COMMON-016: statistic-keyword selections of the default SURVEYMEANS
 * columns. Explicit NOBS MEAN STDERR CLM keeps the N column; CLM STDERR MEAN
 * in any order drops it. Expected listing: SAS 9.4 (SAS/STAT 15.4) output of
 * this program. Invented data (the STAT-COMMON-016 design: strata 1+(x>6),
 * PSU ceil(x/2), weight 1+mod(x,3)).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data sample;
 input x y;
 datalines;
1 4
2 6
3 7
4 9
5 13
6 12
7 17
8 19
9 20
10 23
11 25
12 24
;
run;
data survey; set sample; stratum=1+(x>6); psu=ceil(x/2); sampling_weight=1+mod(x,3); run;
proc surveymeans data=survey nobs mean stderr clm; strata stratum; cluster psu; weight sampling_weight; var y; run;
proc surveymeans data=survey clm stderr mean; strata stratum; cluster psu; weight sampling_weight; var y; run;
