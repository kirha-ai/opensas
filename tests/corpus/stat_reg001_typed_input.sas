/* expect-rc: 1
 * STAT-REG-001: TYPE=CORR / TYPE=COV / TYPE=SSCP input to PROC REG (Input
 * Data Sets, S154 pp. 8588-8590). Every listing below was verified token for
 * token against a SAS 9.4 run of the same statements. Covered: CORR OUTP= with
 * VIF/TOL and TEST; TYPE=COV (COV rows only, and CORR OUTP= with COV, where
 * REG reads the CORR rows); BY groups; a hand-written TYPE=SSCP set with and
 * without its N row (N then comes from the Intercept total, no warning); a
 * TYPE=COV set without N (SAS sets N=10000 and logs a WARNING, hence rc 1);
 * the raw-only options P R CLM CLI DW INFLUENCE PARTIAL, PLOT, PRINT R and
 * OUTPUT are ignored with notes, OUTPUT OUT= being a 0-observation,
 * 0-variable set. No observation counts are printed for summary input.
 * Invented data.
 */
data a; input g x1 x2 y @@; datalines;
1 1 3 2.1 1 2 1 4.3 1 3 4 6.2 1 4 2 8.9 1 5 6 9.7 1 6 5 12.8
2 7 9 13.1 2 8 7 16.4 2 9 8 17.2 2 10 12 21.5 2 11 10 21.9 2 12 11 25.3
;
run;
proc corr data=a outp=c noprint; var x1 x2 y; run;
proc reg data=c; model y = x1 x2 / vif tol; test x1 = x2; run; quit;
proc corr data=a outp=cv cov noprint; var x1 x2 y; run;
data cv2(type=cov); set cv; if _type_ ne 'CORR'; run;
proc reg data=cv2; model y = x1 x2; run; quit;
proc corr data=a outp=cb noprint; by g; var x1 x2 y; run;
proc reg data=cb; by g; model y = x1; run; quit;
data s(type=sscp); input _TYPE_ $ _NAME_ $ Intercept x y; datalines;
SSCP Intercept 5 15 21
SSCP x 15 55 75
SSCP y 21 75 103
N . 5 5 5
;
proc reg data=s; model y=x; run; quit;
data s2(type=sscp); set s; if _type_ ne 'N'; run;
proc reg data=s2; model y=x; run; quit;
data cv3(type=cov); set cv2; if _type_ ne 'N'; run;
proc reg data=cv3; model y = x1; run; quit;
proc reg data=c; model y = x1 / p r clm cli dw influence partial; output out=o p=pp r=rr; plot y*x1; print r; run; quit;
data _null_; file print; id=open('o'); n=attrn(id,'NOBS'); v=attrn(id,'NVARS'); rc=close(id); put 'O ' n= v=; run;
proc reg data=cv; model y = x1; run; quit;
