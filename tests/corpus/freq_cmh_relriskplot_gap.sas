/* expect-rc: 2. STAT-FREQ-014 gap: PLOTS=RELRISKPLOT (and ODDSRATIOPLOT) for
 * stratified 2x2 tables belong to FREQ ODS Graphics (STAT-FREQ-019) and are
 * not implemented. The request must fail loudly (D-009) rather than print
 * the CMH listing while silently omitting the requested graph. Invented data.
 */
options nosyntaxcheck;
data t; input s r c n @@; datalines;
1 1 1 3 1 1 2 1 1 2 1 1 1 2 2 3
2 1 1 2 2 1 2 1 2 2 1 1 2 2 2 2
;
ods graphics on;
proc freq data=t; tables s*r*c / relrisk plots(only)=relriskplot(stats) cmh noprint; weight n; run;
