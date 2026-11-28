/* expect-rc: 2
   STAT-HPPRINCOMP-001 boundary: COV is a valid PROC HPPRINCOMP option whose
   covariance analysis and listing belong to a later ticket; the step must
   fail visibly (D-009 gap) and print nothing. Data invented (D-011). */
options nocenter linesize=160;
data t;
input x y;
datalines;
1 2
2 1
3 4
4 3
;
proc hpprincomp data=t cov;
run;
