/* expect-rc: 1
 * STAT-STDIZE-003: METHOD=ABW(c) / AHUBER(c) / AWAVE(c) (one-step M-estimate
 * of location, A-estimate of scale, INITIAL=), SPACING(p) (with NORM),
 * AGK(p), METHOD=IN(ds) with _TYPE_ or LOCATION / SCALE statements, UNSTD,
 * MISSING=robust method, FREQ, the WEIGHT warning and the "outside the
 * acceptance interval" fallback (p.9445-9454). Invented data; expected = the
 * real SAS 9.4 listing of this program (each step's OUT= values follow it via FILE PRINT); every estimate was also reproduced
 * by an independent calculation (stdize_tests.zig, STAT-STDIZE-003). The rc 1
 * comes from the SAS WARNING "The WEIGHT variable does not apply to
 * METHOD= ABW."
 */
options nodate nonumber nocenter linesize=120;
data a;
input x y w f @@;
datalines;
1 10 1 1 2 12 2 1 3 11 1 2 4 15 3 1 5 14 1 1 7 13 2 1 9 30 1 1 12 16 1 3 20 18 2 1 6 17 1 1
;
proc stdize data=a method=abw(4) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=ahuber(1.5) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=awave(2) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=abw(0.5) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=abw(4) initial=std pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=ahuber(1.5) initial=iqr pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=abw(3) initial=agk(0.3) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=ahuber(2) initial=spacing(0.4) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=ahuber(0.1) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=awave(1) initial=mean pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=ahuber(1.5) pstat out=o; var x y; freq f; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=abw(4) pstat out=o; var x y; weight w; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=spacing(0.5) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=spacing(0.55) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=spacing(0.25) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=spacing(0.95) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=spacing(0.3) norm pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=spacing(0.8) norm pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=spacing(0.5) pstat out=o; var x y; freq f; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=agk(0.5) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=agk(0.2) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=agk(0.35) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=agk(1) pstat out=o; var x y; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=agk(0.3) pstat out=o; var x y; freq f; run;
data _null_; set o; file print; put x 12.8 y 12.8; run;
data b;
set a;
if _n_ = 3 then x = .;
run;
proc stdize data=b method=std missing=abw(4) pstat out=o; var x; run;
data _null_; set o; file print; put x 12.8; run;
proc stdize data=b method=std missing=spacing(0.5) reponly pstat out=o; var x; run;
data _null_; set o; file print; put x 12.8; run;
proc stdize data=b method=std missing=agk(0.5) reponly pstat out=o; var x; run;
data _null_; set o; file print; put x 12.8; run;
proc stdize data=b method=std missing=ahuber(1.5) reponly pstat out=o; var x; run;
data _null_; set o; file print; put x 12.8; run;
data ins;
input _type_ $ x y;
datalines;
LOCATION 2 10
SCALE 4 5
ADD 1 1
MULT 2 2
;
proc stdize data=a method=in(ins) pstat out=o1; var x y; run;
data _null_; set o1; file print; put x 12.8 y 12.8; run;
proc stdize data=o1 method=in(ins) unstd pstat out=o2; var x y; run;
data _null_; set o2; file print; put x 12.8 y 12.8; run;
data ins2;
input _type_ $ x y;
datalines;
LOCATION 2 10
SCALE 4 5
;
proc stdize data=b method=in(ins2) add=1 mult=3 pstat out=o1; var x y; run;
data _null_; set o1; where x ne .; file print; put x 12.8 y 12.8; run;
proc stdize data=o1 method=in(ins2) add=1 mult=3 unstd pstat out=o2; var x y; run;
data _null_; set o2; where x ne .; file print; put x 12.8 y 12.8; run;
proc stdize data=b method=in(ins2) replace pstat out=o1; var x y; run;
data _null_; set o1; file print; put x 12.8 y 12.8; run;
data ls;
input lx ly sx sy;
datalines;
2 10 4 5
3 11 6 7
;
proc stdize data=a method=in(ls) pstat out=o3; var x y; location lx ly; scale sx sy; run;
data _null_; set o3; file print; put x 12.8 y 12.8; run;
proc stdize data=a method=in(ins) pstat out=o4; var x y; freq f; run;
data _null_; set o4; file print; put x 12.8 y 12.8; run;
