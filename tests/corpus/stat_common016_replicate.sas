/* STAT-COMMON-016: replication variance through the shared survey design
 * kernels (src/stat/survey_design.zig): delete-one-PSU jackknife and BRR.
 * Expected listing: SAS 9.4 (SAS/STAT 15.4) output of this program;
 * jackknife SE 1.781669 and BRR SE 2.063236 also equal exact rational
 * enumeration of the replicate means (see the STAT-COMMON-016 Zig tests).
 * Invented data.
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
data survey; set sample; stratum=1+(x>6); psu=ceil(x/2); psu2=ceil(x/3); sampling_weight=1+mod(x,3); run;
proc surveymeans data=survey varmethod=jk; strata stratum; cluster psu; weight sampling_weight; var y x; run;
proc surveymeans data=survey mean stderr varmethod=jk; strata stratum; cluster psu; weight sampling_weight; var y; run;
proc surveymeans data=survey varmethod=brr; strata stratum; cluster psu2; weight sampling_weight; var y; run;
