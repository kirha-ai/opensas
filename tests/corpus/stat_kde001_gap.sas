/* expect-rc: 2
 * STAT-KDE-001: ODS Graphics plots of PROC KDE (owned by STAT-KDE-009) are a
 * loud D-009 gap: with ODS GRAPHICS ON the BIVAR statement draws a default
 * contour plot, so the step fails visibly and prints nothing. The default
 * UNIVAR bandwidth (Sheather-Jones plug-in, STAT-KDE-006) is a gap as well.
 * Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
data t;
input x y @@;
datalines;
0 0 1 1 2 3 3 2 4 4 5 5 6 7 7 6 8 8 9 9
;
ods graphics on;
proc kde data=t;
bivar x y;
run;
ods graphics off;
proc kde data=t;
univar x;
run;
