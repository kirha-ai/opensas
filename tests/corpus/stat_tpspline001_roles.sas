/* STAT-TPSPLINE-001: variable roles, observation selection and missing
 * values against a SAS 15.4 reference run: two BY groups, WHERE selection,
 * an observation with a missing response (counted, excluded), ID statements
 * (no listing effect, p.10303), no LOGNLAMBDA= (no GCV Function table), a
 * FREQ variable (integer portion used, observations replicated, p.10303) and
 * ALPHA= on the Bayesian confidence limits, and the OUTPUT keyword order and
 * values of StD_, R_ and Adiag_ (their order and labels are unit-tested in
 * src/stat/tpspline_tests.zig). Invented data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote; ods graphics off;
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
data two;
set surface(in=a) surface(in=b);
g = 1 + b;
nm = 'r' || put(_n_, z3.);
output;
if _n_ = 7 then do; y = 999; output; end;
if g = 2 and _n_ = 60 then do; y = .; output; end;
run;
proc tpspline data=two;
where y < 900;
by g;
id nm;
id rep;
model y=(x1 x2);
run;
data fq;
set surface;
if x1 + x2 = -1.5 then do;
  if rep = 2 then delete;
  f = 2;
end;
else f = 1.5;
run;
proc tpspline data=fq;
freq f;
model y=(x1 x2) / lognl=(-2 -1.5);
output out=ofq;
run;
data _null_;
file print;
set ofq end=last;
retain ok 1;
if _n_ = 3 and abs(p_y - 3.33759) > 5e-6 then ok = 0;
if _n_ = 1 and abs(p_y - 4.54597) > 5e-6 then ok = 0;
if last then put 'freq rows=' _n_ 'ok=' ok;
run;
proc tpspline data=surface;
model y=(x1 x2) / alpha=0.1;
output out=oal lclm uclm pred;
run;
data _null_;
file print;
set oal end=last;
retain ok 1;
/* 95% reference row 1: P 4.54597 UCLM 4.60339; half-width scales with
   probit(0.95)/probit(0.975). */
if _n_ = 1 and abs((uclm_y - p_y) - (4.60339 - 4.54597) * probit(0.95) / probit(0.975)) > 2e-5 then ok = 0;
if abs((uclm_y - p_y) - (p_y - lclm_y)) > 1e-9 then ok = 0;
if last then put 'alpha rows=' _n_ 'ok=' ok;
run;
proc tpspline data=surface;
model y=(x1 x2);
output out=okw adiag std resid uclm lclm pred;
run;
data _null_;
file print;
set okw end=last;
retain ok 1;
/* SAS 15.4 reference rows 1-3 (StD_y R_y Adiag_y). */
if _n_ = 1 and (abs(std_y - 0.02929789515058) > 1e-9 or abs(r_y - 0.00806403806383) > 1e-9 or abs(adiag_y - 0.39642) > 5e-6) then ok = 0;
if _n_ = 2 and (abs(std_y - 0.02929789515058) > 1e-9 or abs(r_y - 0.05403380747701) > 1e-9) then ok = 0;
if _n_ = 3 and (abs(std_y - 0.02639753860553) > 1e-9 or abs(r_y - 0.00017138920836) > 1e-9 or abs(adiag_y - 0.32181) > 5e-6) then ok = 0;
if last then put 'keywords rows=' _n_ 'ok=' ok;
run;
