/* expect-rc: 2
   STAT-MULTTEST-001 boundary: the BOOTSTRAP adjustment (like PERMUTATION and
   the step-down and FDR resampling forms) depends on the SAS random stream,
   which is not reproduced. The step must fail visibly (D-009 gap) and print
   no table at all, never adjusted p-values from a different stream. The
   closed-form step that follows the gap is not reached either way.
   Data: published SAS/STAT 15.4 ch.86 Getting Started sample (Drug). */
options nodate nonumber nocenter linesize=160;
title;
data Drug;
input Dose$ SideEff1-SideEff10;
datalines;
0MG 0 0 1 0 0 1 0 0 0 0
0MG 0 0 0 0 0 0 0 0 0 1
0MG 0 0 0 0 0 0 0 0 1 0
0MG 0 0 0 0 0 0 0 0 0 0
0MG 0 1 0 0 0 0 0 0 0 0
1MG 1 0 0 1 0 1 0 0 1 0
1MG 0 0 0 1 1 0 0 1 0 1
1MG 0 1 0 0 0 0 1 0 0 0
1MG 0 0 1 0 0 0 0 0 0 1
1MG 1 0 1 0 0 0 0 1 0 0
2MG 0 1 1 1 0 1 1 1 0 1
2MG 1 1 1 1 1 1 0 1 1 0
2MG 1 0 0 1 0 1 1 0 1 0
2MG 0 1 1 1 1 0 1 1 1 1
2MG 1 0 1 0 1 1 1 0 0 1
;
proc multtest bootstrap nsample=199 seed=41287 notables;
class Dose;
test ca(SideEff1-SideEff10);
contrast 'Trend' 0 1 2;
run;
