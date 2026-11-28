/* STAT-TPSPLINE-001: FREQ, BY, DATA= default and PLOTS rules against a SAS
 * 15.4 reference run (listing below produced by SAS 15.4 from this program).
 * FREQ (p.10303): values below one and missing values drop the observation
 * without counting it as missing (NOTE only for non-missing values below
 * one); only the integer portion is used; a missing smoothing variable counts
 * the observation as missing whatever its frequency; unique design points
 * count used observations only. BY (p.10302): only the last BY statement is
 * used; DESCENDING and NOTSORTED groups. DATA= defaults to the most recently
 * created data set (p.10298); with two DATA= options the first is used (a
 * WARNING); data set options apply. PLOTS= with ODS Graphics off only warns,
 * once even for two PLOTS options. ID takes character and numeric variables
 * and lists (p.10303) with no listing effect. A missing BY value is its own
 * (first) group; formatted BY values label the BY lines.
 * Invented data.
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
data fq;
set surface;
f = 1;
if _n_ = 3 then f = 0.5;
if _n_ = 5 then f = .;
if _n_ = 7 then f = 0;
if _n_ = 9 then f = -2;
if _n_ = 11 then f = 2.7;
run;
title 'A freq below one, missing, truncated';
proc tpspline data=fq;
freq f;
model y=(x1 x2);
run;
data k1; set surface; f=1; if _n_ in (1,2) then f=0; if _n_=3 then do; y=.; f=0; end; if _n_=5 then do; x1=.; f=.; end; run;
title 'B unique points and combinations';
proc tpspline data=k1;
freq f;
model y=(x1 x2);
run;
data kb; set surface; f=1; if _n_=3 then do; x1=.; f=.; end; run;
data kc; set surface; f=1; if _n_=3 then do; y=.; f=.; end; run;
data kd; set surface; f=1; if _n_=3 then do; y=.; f=0.5; end; run;
data kg; set surface; f=1; if _n_=3 then f=.; run;
data kh; set surface; f=1; if _n_=3 then do; x2=.; f=0; end; run;
title 'C x missing, freq missing'; proc tpspline data=kb; freq f; model y=(x1 x2); run;
title 'D y missing, freq missing'; proc tpspline data=kc; freq f; model y=(x1 x2); run;
title 'E y missing, freq 0.5'; proc tpspline data=kd; freq f; model y=(x1 x2); run;
title 'F freq missing'; proc tpspline data=kg; freq f; model y=(x1 x2); run;
title 'G x missing, freq 0'; proc tpspline data=kh; freq f; model y=(x1 x2); run;
data two;
set surface(in=a) surface(in=b);
g = 1 + b; h = 3 - g;
if g = 2 then y = y + 0.05*x1;
run;
title 'H default data';
proc tpspline;
model y=(x1 x2);
run;
title 'I two BY statements';
proc tpspline data=two;
by h;
by g;
model y=(x1 x2);
run;
proc sort data=two out=twod; by descending g; run;
title 'J BY DESCENDING';
proc tpspline data=twod;
by descending g;
model y=(x1 x2);
run;
title 'K BY NOTSORTED';
proc tpspline data=twod;
by g notsorted;
model y=(x1 x2);
run;
title 'L PLOTS with ODS Graphics off';
proc tpspline data=surface plots(only)=(fit residualHistogram residuals(smooth unpack));
model y=(x1 x2);
run;
data other; set surface; y = y + x1*x2; nm = 'r' || put(_n_, z3.); run;
title 'M two DATA= options'; proc tpspline data=other data=surface; model y=(x1 x2); run;
title 'N data set options'; proc tpspline data=surface(where=(x1 > -1) rename=(y=yy)); model yy=(x1 x2); run;
title 'O two PLOTS options'; proc tpspline data=surface plots=none plots=fit; model y=(x1 x2); run;
title 'P ID lists'; proc tpspline data=other; id nm rep x1-x2; model y=(x1 x2); run;
proc format; value gf 1 = 'first' 2 = 'second'; run;
data three; set surface(in=a) surface(in=b) surface(in=c); if a then g = .; else if b then g = 1; else g = 2; if g = 1 then y = y + 0.05*x2; format g gf.; run;
title 'Q BY with a missing level and a format'; proc tpspline data=three; by g; model y=(x1 x2); run;
