/* STAT-PLM-007: LSMEANS / one-sided LSMESTIMATE / SLICE from a restored GLM
 * store. Data and expected tables: the published SAS/STAT 15.4 PLM "Getting
 * Started" block design; every table below is the SAS listing of that example
 * (LSMEANS a / DIFF; LSMESTIMATE rows with UPPERTAILED; SLICE a*b /
 * SLICEBY(b='1') DIFF with ODS GRAPHICS OFF). The joint FTEST table of the
 * published LSMESTIMATE step is not requested here: its chi-bar-square
 * p-value is simulation-based (see stat_plm_lsmeans_gap.sas).
 * NOINFO keeps the wall-clock Store Information table out of the fixture. */
data BlockDesign;
input block a b y @@;
datalines;
1 1 1 56 1 1 2 41
1 2 1 50 1 2 2 36
1 3 1 39 1 3 2 35
2 1 1 30 2 1 2 25
2 2 1 36 2 2 2 28
2 3 1 33 2 3 2 30
3 1 1 32 3 1 2 24
3 2 1 31 3 2 2 27
3 3 1 15 3 3 2 19
4 1 1 30 4 1 2 25
4 2 1 35 4 2 2 30
4 3 1 17 4 3 2 18
;
proc glm data=BlockDesign noprint;
class block a b;
model y = block a b a*b;
store work.BlockAnalysis / label='PLM: Getting Started';
run;
proc plm restore=work.BlockAnalysis noinfo seed=3;
lsmeans a / diff;
lsmestimate a -1 1,
1 1 -2 / uppertailed;
run;
proc plm restore=work.BlockAnalysis noinfo;
slice a*b / sliceby(b='1') diff;
run;
