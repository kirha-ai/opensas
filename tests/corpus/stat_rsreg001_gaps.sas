/* expect-rc: 2
 * STAT-RSREG-001: valid PROC RSREG syntax owned by later tickets must fail
 * visibly (D-009 gap), never silently: RIDGE (STAT-RSREG-004). The other
 * gaps (OUT=, COVAR=, output statistics, NOCODE, PRESS, several responses,
 * PLOTS= under ODS GRAPHICS, ODS routing) are asserted through the captured
 * reporter in src/stat/rsreg.zig and stat_rsreg001_plots_gap.sas. Invented data.
 */
data s; input y x1 x2 @@; datalines;
5 -1 -1  9 -1 1  8 1 -1  2 1 1  6 0 0  7 0 0  4 0 1  3 1 0  9 -1 0  6 0 -1
;
proc rsreg data=s; model y = x1 x2; ridge max; run;
