/* STAT-GLMMOD-001: an empty input data set. SAS 9.4 writes only the NOTEs
 * "No observations in data set WORK.E." and "stopped processing this step",
 * prints no listing and creates no OUTDESIGN=; no ERROR, so rc stays 0.
 * Invented data.
 */
data e;
input g $ y;
if y > 100;
datalines;
A 1
B 2
;
proc glmmod data=e outdesign=d; class g; model y=g; run;
