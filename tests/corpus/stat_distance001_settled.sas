/* STAT-DISTANCE-001: PROC DISTANCE rules the chapter does not state, settled
 * by a SAS 9.4 run of these same steps on invented data: a later BY group
 * larger than the first widens the matrix and pads the smaller groups (BY
 * values kept, COPY blank, FREQ/WEIGHT and distances missing even with
 * UNDEF=); MULT= is ignored without standardization unless NOSTD is given;
 * several VAR statements add their lists; a repeated METHOD= or PREFIX=
 * keeps the last value; WEIGHTS= start TO stop BY increment. Expected
 * output is the SAS listing of the same program (C3 shown without the blank
 * COPY value, which is checked separately).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
%macro show(ds, lab);
data _null_; file print; if _n_=1 then put "=== &lab"; set &ds; put _all_; run;
%mend;
data a; input id $ g $ x z c $ f w; datalines;
p A 1 1 k 1 1
q A 2 5 l 2 2
r A 4 3 m 1 1
p B 3 5 n 1 1
q B 6 1 o 1 2
r B 8 4 s 1 1
t B 9 9 u 1 1
;
data z; input x z; datalines;
1 5
2 5
4 5
;
data m; input x z; datalines;
1 1
2 .
4 3
7 2
. 5
;
proc distance data=a out=c2 method=euclid; var interval(x z/std=std); by g; run; %show(c2,C2 bigger)
data a2; set a; if g='A' then g='C'; run; proc sort data=a2; by g; run;
proc distance data=a2 out=c3 method=euclid undef=-1; var interval(x z/std=std); by g; copy c; freq f; weight w; run; %show(c3(drop=c),C3 pad)
data _null_; set c3; file print; if c=' ' then put 'blank c at ' _n_=; run;
proc distance data=z out=c6 method=euclid mult=2 add=1; var interval(x); run; %show(c6,C6 mult nostd single level)
proc distance data=z out=c6b method=euclid nostd mult=2 add=1; var interval(x z); run; %show(c6b,C6b nostd mult)
data a7; set a; where g='A'; run;
proc distance data=a7 out=c9 method=euclid; var interval(x/std=std); var interval(z/std=std); run; %show(c9,C9 twovar)
proc distance data=a7 out=c9e method=euclid method=cityblock; var interval(x z/std=std); run; %show(c9e,C9e twomethod)
proc distance data=m out=c11 method=euclid; var interval(x z/std=std weights=1 to 2 by 1); run; %show(c11,C11 toby)
proc distance data=a7 out=c13 method=euclid prefix=A prefix=B; var interval(x z/std=std); run; %show(c13,C13 twoprefix)
