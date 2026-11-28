/* expect-rc: 2
 * STAT-REG-001: PROC CORR OUTP= is TYPE=CORR (SAS 9.4 ATTRC run, also with
 * COV/SSCP/CSSCP/ALPHA/PARTIAL/WITH and for OUTS=/OUTK=/OUTH=/OUTPLC=/OUTPLS=).
 * PROC REG must therefore read it as a correlation matrix (Input Data Sets,
 * S154 pp. 8588-8590). That mode is not implemented, so it is a loud gap; it
 * used to fit the MEAN/STD/N/CORR rows as five observations and exit 0.
 * Invented data; no listing may be produced.
 */
data a; input x y @@; datalines;
1 2 2 4 3 7 4 8 5 11
;
run;
proc corr data=a outp=c noprint; var x y; run;
proc reg data=c; model y = x; run;
