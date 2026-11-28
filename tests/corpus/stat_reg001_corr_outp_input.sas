/* STAT-REG-001: PROC CORR OUTP= is TYPE=CORR (SAS 9.4 ATTRC run, also with
 * COV/SSCP/CSSCP/ALPHA/PARTIAL/WITH and for OUTS=/OUTK=/OUTH=/OUTPLC=/OUTPLS=),
 * so PROC REG reads it as a correlation matrix (Input Data Sets, S154
 * pp. 8588-8590), not as five observations. The listing equals a SAS 9.4 run
 * of this program token for token (no observation counts are printed).
 * Invented data.
 */
data a; input x y @@; datalines;
1 2 2 4 3 7 4 8 5 11
;
run;
proc corr data=a outp=c noprint; var x y; run;
proc reg data=c; model y = x; run;
