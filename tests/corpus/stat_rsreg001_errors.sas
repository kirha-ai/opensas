/* expect-rc: 1
 * STAT-RSREG-001: documented invalid inputs, each a visible ERROR (wording
 * from a SAS 9.4 reference run): no MODEL statement, an unknown variable,
 * an empty input (SAS prints the default coding page, M=0 and S=1, then
 * "No non-missing observations to process."), a WEIGHT that is never
 * positive (same), and an out-of-order BY value (the first group prints,
 * then the sort ERROR). Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data s; input y x1 x2 w g @@; datalines;
5 -1 -1 0 2  9 -1 1 0 2  8 1 -1 0 2  2 1 1 0 2  6 0 0 0 2  7 0 0 0 2  4 0 1 0 2  3 1 0 0 2  9 -1 0 0 2  6 0 -1 0 2
5 -1 -1 0 1  9 -1 1 0 1  8 1 -1 0 1  2 1 1 0 1  6 0 0 0 1  7 0 0 0 1  4 0 1 0 1  3 1 0 0 1  9 -1 0 0 1  6 0 -1 0 1
;
title 'E1 no model';
proc rsreg data=s; run;
title 'E2 unknown variable';
proc rsreg data=s; model y = nosuch; run;
data e; set s; stop; run;
title 'E3 empty input';
proc rsreg data=e; model y = x1 x2; run;
title 'E4 weight never positive';
proc rsreg data=s; model y = x1 x2; weight w; run;
title 'E5 unsorted BY';
proc rsreg data=s; by g; model y = x1 x2 / noanova; run;
