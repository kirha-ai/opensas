/* STAT-FREQ-019: ODDSRATIOPLOT (ODS graph ORPlot) for a 2 x 2 x 2 table (S154 Table 47.23).
 * Invented data: stratum odds ratios 9 and 4, Mantel-Haenszel common odds ratio 43/7. */
options nodate nonumber;
ods listing gpath="%sysfunc(pathname(work))";
data t; input s r c n @@; datalines;
1 1 1 3 1 1 2 1 1 2 1 1 1 2 2 3
2 1 1 2 2 1 2 1 2 2 1 1 2 2 2 2
;
ods graphics on;
proc freq data=t; tables s*r*c / or plots(only)=oddsratioplot(stats logbase=10) cmh noprint; weight n; run;
proc freq data=t; tables s*r*c / cmh plots(only)=oddsratioplot noprint; weight n; run;
ods graphics off;
