/* expect-rc: 2. STAT-FREQ-019 gap: PLOTS=RISKDIFFPLOT for stratified 2x2
 * tables (S154 Table 47.23) has no renderer yet. The request must fail loudly
 * (D-009) rather than print the CMH listing while silently omitting the
 * requested graph. This fixture formerly pinned the same gap for RELRISKPLOT,
 * which STAT-FREQ-019 implemented (see stat_graphics_freq_relriskplot).
 * Invented data.
 */
options nosyntaxcheck;
data t; input s r c n @@; datalines;
1 1 1 3 1 1 2 1 1 2 1 1 1 2 2 3
2 1 1 2 2 1 2 1 2 2 1 1 2 2 2 2
;
ods graphics on;
proc freq data=t; tables s*r*c / riskdiff plots(only)=riskdiffplot(stats) cmh noprint; weight n; run;
