/* STAT-MODECLUS-001: variable roles, options and missing values against a
 * SAS 15.4 reference run on the published Getting Started data: BY groups,
 * a nonintegral FREQ variable (truncated, p.6826), an ID variable (no _OBS_
 * in OUT=), a missing coordinate (excluded, p.6837), a METHOD= list (Method
 * column in the summary), boundary observations with estimated saddle
 * densities, DR=/CR= with NOSUMMARY, SHORT, and the default R= first guess
 * (p.6827) without a VAR statement.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data example;
input x y @@;
datalines;
18 18 20 22 21 20 12 23 17 12 23 25 25 20 16 27
20 13 28 22 80 20 75 19 77 23 81 26 55 21 64 24
72 26 70 35 75 30 78 42 18 52 27 57 41 61 48 64
59 72 69 72 80 80 31 53 51 69 72 81
;
title 'P3 method0 by freq id missing';
data ex3;
set example;
g = (_n_ > 15);
w = 1 + mod(_n_,3) + 0.5;
nm = 'o' || put(_n_, z2.);
if _n_ = 4 then x = .;
run;
proc modeclus data=ex3 method=0 1 r=12 out=o3;
by g; freq w; id nm; var x y;
run;
data _null_;
file print;
set o3 end=last;
retain ok 1;
/* SAS 15.4 reference rows 1-8 (g=0, METHOD=0): DENSITY .001421026 x3, .,
   .000947351 .001105243 .001421026 .000947351; CLUSTER 1 except row 4. */
if _n_ <= 8 then do;
  if _n_ = 4 then do;
    if density ne . or cluster ne . then ok = 0;
  end;
  else if abs(density - choosen(_n_, .001421026, .001421026, .001421026, 0, .000947351, .001105243, .001421026, .000947351)) >= 5e-10
     or cluster ne 1 or _r_ ne 12 or _method_ ne 0 then ok = 0;
end;
if last then put 'rows=' _n_ 'ok=' ok;
run;
title 'P4 dr cr';
proc modeclus data=example method=1 dr=10 cr=15 nosummary;
var x y;
run;
title 'P5 short';
proc modeclus data=example method=1 r=10 short;
var x y;
run;
title 'P6 default r';
proc modeclus data=example method=1;
run;
