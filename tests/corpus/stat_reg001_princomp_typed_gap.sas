/* expect-rc: 2
 * STAT-REG-001 probe: PROC PRINCOMP reads TYPE=CORR/COV/SSCP/... input as a
 * matrix (S154 PRINCOMP "Input Data Set"). That mode is not implemented, so a
 * CORR OUTP= set (TYPE=CORR, SAS 9.4 ATTRC run) is a loud gap instead of
 * having its MEAN/STD/N/CORR rows analysed as observations. Invented data.
 */
data a; input x y @@; datalines;
1 2 2 4 3 7 4 8 5 11
;
run;
proc corr data=a outp=c noprint; var x y; run;
proc princomp data=c; var x y; run;
