/* STAT-MULTTEST-001: PROC MULTTEST skeleton -- CLASS/TEST CA/CONTRAST roles,
 * NOTABLES, Model Information, Contrast Coefficients and p-Values with the
 * closed-form BONFERRONI adjustment. Data: published SAS/STAT 15.4 ch.86
 * Getting Started sample (Drug). The Raw column and the layout were checked
 * against the SAS listing of the same analysis; Bonferroni = min(1, 10 p)
 * by hand from the unrounded Cochran-Armitage p-values. */
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
proc multtest bonferroni notables;
class Dose;
test ca(SideEff1-SideEff10);
contrast 'Trend' 0 1 2;
run;
