/* expect-rc: 1
 * STAT-LIFEREG-001: the MODEL statement is required; a step without one is a
 * user error, not a gap. Invented data.
 */
data relief;
input minutes censor;
datalines;
11 0
14 1
;
run;
proc lifereg data=relief;
weight minutes;
run;
