/* expect-rc: 2
 * STAT-STDIZE-003: valid PROC STDIZE requests that stay loud D-009 gaps:
 * METHOD=L(p) (the PROC FASTCLUS LEAST=p iteration; SAS L(1.5) is not the
 * exact minimizer), SNORM with SPACING, NORM with AGK and BY groups with
 * METHOD=IN. Nothing is printed for these steps. Invented data.
 */
options nodate nonumber nocenter linesize=120;
data a;
input g x @@;
datalines;
1 1 1 2 1 3 1 4 1 5 2 7 2 9 2 12 2 20 2 6
;
proc stdize data=a method=l(1.5) pstat; var x; run;
proc stdize data=a method=spacing(0.5) snorm pstat; var x; run;
proc stdize data=a method=agk(0.5) norm pstat; var x; run;
data ins;
input _type_ $ x;
datalines;
LOCATION 2
SCALE 4
;
proc stdize data=a method=in(ins) pstat; var x; by g; run;
