/* STAT-TPSPLINE-001: the default thin-plate smoothing spline with a
 * LOGNLAMBDA= list (S154 Chapter 125, PROC TPSPLINE/MODEL/OUTPUT statements):
 * Summary of Input Data Set, Summary of Final Model, GCV Function (minimum
 * marked) and the Summary Statistics of the GCV-minimizing fit, all from a
 * SAS 15.4 reference run; the OUT= data set (P_, LCLM_, UCLM_ in that order
 * whatever the keyword order) is checked against the reference rows 1-12 in
 * a DATA step, because the PROC PRINT decimal alignment of the original is a
 * known Base blocker. Invented data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data surface;
do x1=-1 to 1 by 0.5;
do x2=-1 to 1 by 0.5;
do rep=1 to 2;
y=3+x1-2*x2+0.5*x1*x2+0.1*cos(rep+x1+x2);
output;
end;
end;
end;
run;
proc tpspline data=surface;
model y=(x1 x2) / lognlambda=(-4 to -2.5 by 0.5);
output out=predicted pred uclm lclm;
run;
/* SAS 15.4 reference OUT= rows 1-12: P_y LCLM_y UCLM_y. */
data ref;
input p l u @@;
datalines;
4.54597 4.48854 4.60339 4.54597 4.48854 4.60339 3.33759 3.28585 3.38933
3.33759 3.28585 3.38933 2.07518 2.02358 2.12678 2.07518 2.02358 2.12678
0.79397 0.74223 0.84571 0.79397 0.74223 0.84571 -0.45598 -0.51340 -0.39855
-0.45598 -0.51340 -0.39855 4.83759 4.78585 4.88933 4.83759 4.78585 4.88933
;
data _null_;
file print;
merge predicted ref(in=inref) end=last;
retain ok 1;
if inref then do;
  if abs(p_y - p) > 5e-6 or abs(lclm_y - l) > 5e-6 or abs(uclm_y - u) > 5e-6 then ok = 0;
end;
if last then put 'rows=' _n_ 'ok=' ok;
run;
