/* STAT-STDIZE-001: NORM with METHOD=IQR (p.9446) and the PSTAT Norm column.
 * Invented data; expected = the real SAS 9.4 listing of this step: x = 1, 2,
 * 3, 6, 10, median 3, IQR 6 - 2 = 4 (PCTLDEF=5), Norm 4 / (2 * 0.6744897502)
 * = 2.965204.
 */
options nodate nonumber nocenter linesize=120;
data d;
input x @@;
datalines;
1 2 3 6 10
;
proc stdize data=d out=q1 method=iqr norm pstat; var x; run;
