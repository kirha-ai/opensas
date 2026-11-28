/* STAT-FREQ-019: RELRISKPLOT for a 2 x 2 x 2 table (S154 Table 47.23). Invented data:
 * stratum relative risks 3 and 2, Mantel-Haenszel common relative risk 2.5. */
options nodate nonumber;
ods listing gpath="%sysfunc(pathname(work))";
data t; input s r c n @@; datalines;
1 1 1 3 1 1 2 1 1 2 1 1 1 2 2 3
2 1 1 2 2 1 2 1 2 2 1 1 2 2 2 2
;
ods graphics on;
proc freq data=t; tables s*r*c / relrisk plots(only)=relriskplot(stats) cmh noprint; weight n; run;
proc freq data=t; tables s*r*c / relrisk plots(only)=relriskplot(column=2 logbase=2 common=no) cmh noprint; weight n; run;
ods graphics off;
proc freq data=t; tables s*r*c / relrisk plots(only)=relriskplot cmh noprint; weight n; run;
