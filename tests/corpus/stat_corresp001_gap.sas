/* expect-rc: 2
 * STAT-CORRESP-001: under ODS GRAPHICS ON the default inertia chart and
 * configuration plot (STAT-CORRESP-008) are not implemented. The tables SAS
 * prints with them (p.2571: the chart replaces the inertia table) are
 * printed, and the step still ends with a visible D-009 gap. TABLES input
 * (STAT-CORRESP-003) is a loud gap that prints nothing. Invented data;
 * coordinates are the SAS 9.4 listing of the same table.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data S;
input a b c;
datalines;
3 5 7
4 1 2
9 2 5
;
ods graphics on;
proc corresp data=S short;
var a b c;
run;
ods graphics off;
proc corresp data=S;
tables a, b;
run;
