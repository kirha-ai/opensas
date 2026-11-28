/* expect-rc: 2
 * STAT-REG-001: summary-input forms that are not implemented stay loud.
 * SAS treats a TYPE=CORR set without a MEAN observation as having zero means
 * (SAS 9.4 run: Dependent Mean 0, Intercept 0); that, REWEIGHT/PAINT, FREQ,
 * WEIGHT, ID, OUTEST= and the DATA=(TYPE=) override are gaps here. A gap ends
 * the run, so only the first is exercised. Invented data.
 */
data a; input x y @@; datalines;
1 2 2 4 3 7 4 8 5 11
;
run;
proc corr data=a outp=c noprint; var x y; run;
data c4(type=corr); set c; if _type_ ne 'MEAN'; run;
proc reg data=c4; model y = x; run; quit;
