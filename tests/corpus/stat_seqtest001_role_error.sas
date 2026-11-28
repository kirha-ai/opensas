/* expect-rc: 1
   STAT-SEQTEST-001: with PARMS(TESTVAR=) the PARMS= data set must contain
   the Estimate variable (p.9169). Here it is absent, so the step is a user
   error and prints nothing. Boundary rows: the 4-stage two-sided
   O'Brien-Fleming design values printed by SAS 9.4; estimate data invented. */
options nocenter;
title;
data boundaries;
length _Scale_ $4 _Stop_ $6 _ALT_ $8;
_Scale_='StdZ'; _Stop_='Reject'; _ALT_='TwoSided';
input _Stage_ _InfoProp_ _Info_ AltRef_L AltRef_U Bound_LA Bound_UA;
datalines;
1 0.25 0.026851 -1.63862 1.63862 -4.04859 4.04859
2 0.50 0.053701 -2.31736 2.31736 -2.86278 2.86278
3 0.75 0.080552 -2.83817 2.83817 -2.33745 2.33745
4 1.00 0.107403 -3.27724 3.27724 -2.02429 2.02429
;
data estimates;
length Variable $8 _Scale_ $8;
Variable='Trt'; _Scale_='MLE'; _Stage_=1; StdErr=4.5;
run;
proc seqtest boundary=boundaries parms(testvar=Trt)=estimates;
run;
