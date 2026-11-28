/* expect-rc: 1
 * STAT-STDIZE-004: PROC STDIZE Computing Quantiles (pp.9455-9456), invented
 * data. PCTLDEF=1..5 for METHOD=MEDIAN, IQR and MAD with n = 6, 7, 8 and 10
 * (np integral, fractional and exactly one half), FREQ (integer) with
 * PCTLDEF=1; weighted percentiles for WEIGHT, FREQ / NOTRUNCATE and WEIGHT
 * with FREQ (cumulative weight equal to pW gives x_i, the SAS 15.4
 * behaviour, not the guide's average); the two PCTLDEF= WARNINGs.
 * Expected output is the real SAS 9.4 (SAS/STAT 15.4) listing of this
 * program; hand checks: a10 PCTLDEF=1 IQR (.5*34+.5*55) - (.5*3+.5*5) = 40.5,
 * PCTLDEF=4 (.75*55+.25*89) - (.25*3+.75*5) = 59; a7 PCTLDEF=2 25 - 4 = 21.
 * rc 1 comes from the SAS WARNINGs.
 */
options nodate nonumber nocenter linesize=120 pagesize=max;
title;
data a10; input x @@; w = 2; datalines;
2 3 5 8 13 21 34 55 89 144
;
data a7; input x @@; datalines;
49 1 36 4 25 9 16
;
data a6; input x @@; datalines;
10 20 30 40 50 60
;
data t8; input x f @@; datalines;
1 1 2 1 3 1 4 1 5 1 6 1 7 1 8 1
;
%macro defs(ds);
%do d = 1 %to 5;
  %do m = 1 %to 3;
    %let meth = %scan(median iqr mad, &m);
    proc stdize data=&ds method=&meth pctldef=&d out=o; var x; run;
    data _null_; set o; file print; put "&ds &meth def=&d " x 14.9; run;
  %end;
%end;
%mend;
%defs(a10)
%defs(a7)
%defs(a6)
%defs(t8)
proc stdize data=t8 method=median pctldef=1 out=o pstat; var x; freq f; run;
data w; input x w f @@; datalines;
1 1 1.5 2 2 0.5 3 0.5 2.5 4 3 1 5 1 0.25 6 2.5 3
;
%macro wt;
%do m = 1 %to 3;
  %let meth = %scan(median iqr mad, &m);
  proc stdize data=w method=&meth out=o; var x; weight w; run;
  data _null_; set o; file print; put "W &meth " x 14.9; run;
  proc stdize data=w method=&meth out=o pctldef=1; var x; weight w; run;
  data _null_; set o; file print; put "W def1 &meth " x 14.9; run;
  proc stdize data=w method=&meth out=o pstat; var x; freq f / notruncate; run;
  data _null_; set o; file print; put "FN &meth " x 14.9; run;
  proc stdize data=w method=&meth out=o pstat; var x; freq f; run;
  data _null_; set o; file print; put "FT &meth " x 14.9; run;
  proc stdize data=a10 method=&meth out=o; var x; weight w; run;
  data _null_; set o; file print; put "E &meth " x 14.9; run;
%end;
%mend;
%wt
data w4; input x w @@; datalines;
1 1 2 1 3 2 4 1 5 3
;
proc stdize data=w4 method=iqr out=o; var x; weight w; run;
data _null_; set o; file print; put "W4 iqr " x 14.9; run;
data wf; input x w f @@; datalines;
1 1 2 2 2 1 3 0.5 1 4 3 1 5 1 2
;
proc stdize data=wf method=median out=o; var x; weight w; freq f; run;
data _null_; set o; file print; put "WF median " x 14.9; run;
proc stdize data=wf method=iqr out=o; var x; weight w; freq f; run;
data _null_; set o; file print; put "WF iqr " x 14.9; run;
proc stdize data=wf method=mad pctldef=3 out=o pstat; var x; freq f / notruncate; run;
proc stdize data=wf method=std pctldef=1 out=o; var x; weight w; run;
data _null_; set o; file print; put "WF std " x 14.9; run;
