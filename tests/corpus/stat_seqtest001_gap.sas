/* expect-rc: 2
   STAT-SEQTEST-001 boundary: PROC SEQTEST reads and validates the BOUNDARY=
   and PARMS= data sets (roles, codes, Table 111.2 boundary variables, the
   TESTVAR= row and its StdErr information level), but the group sequential
   boundary computation and the Design/Test Information tables are owned by
   STAT-SEQTEST-002/003. The step must fail visibly (D-009 gap) and print
   nothing, never approximate boundaries. The boundary rows are the 4-stage
   two-sided O'Brien-Fleming "Boundary Information" values that SAS 9.4 prints
   for PROC SEQDESIGN ALTREF=-10 NSTAGES=4 METHOD=OBF; the estimate is invented. */
options nocenter;
title;
data boundaries;
length _Scale_ $4 _Stop_ $6 _ALT_ $8;
_Scale_='StdZ'; _Stop_='Reject'; _ALT_='TwoSided';
input _Stage_ _InfoProp_ _Info_ N AltRef_L AltRef_U Bound_LA Bound_UA;
datalines;
1 0.25 0.026851 42.96116 -1.63862 1.63862 -4.04859 4.04859
2 0.50 0.053701 85.92233 -2.31736 2.31736 -2.86278 2.86278
3 0.75 0.080552 128.8835 -2.83817 2.83817 -2.33745 2.33745
4 1.00 0.107403 171.8447 -3.27724 3.27724 -2.02429 2.02429
;
data estimates;
length Variable $8 _Scale_ $8;
Variable='Trt'; _Scale_='MLE'; _Stage_=1; Estimate=-7; StdErr=4.5;
run;
proc seqtest boundary=boundaries parms(testvar=Trt)=estimates infoadj=prop;
run;
