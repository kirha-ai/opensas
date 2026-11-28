/* expect-rc: 1
 * STAT-STDIZE-004: PROC STDIZE Constant Data (p.9456) and the degenerate
 * samples of Computation of the Statistics, invented data. Constant
 * variables (every method), a zero MAD / IQR / SUM scale of nonconstant data,
 * one usable value and BY groups with no usable value: the scale is set to
 * missing, the variable is copied unstandardized, with the SAS WARNINGs
 * ("scale estimator ... less than or equal to 0" or "can not be computed"),
 * the acceptance-interval NOTE for ABW/AHUBER/AWAVE and the AGK NOTE; a
 * missing value then becomes MISSING=value, or the location with REPONLY,
 * and stays missing with REPLACE or MISSING=method. Also USTD with
 * VARDEF=DF/WDF (divisor n / sum of weights, with NOTEs) and a FUZZ= zero
 * scale (reported 0, values still divided by the computed scale).
 * Expected output is the real SAS 9.4 (SAS/STAT 15.4) listing of this program
 * without the blank line SAS writes before each FILE PRINT page (a known
 * listing difference owned outside STDIZE). rc 1 comes from the WARNINGs.
 */
options nodate nonumber nocenter linesize=120 pagesize=max;
title;
%macro show(tag);
data _null_; set o; file print;
  if missing(x) then put "&tag " 'missing'; else put "&tag " x 14.9;
run;
%mend;
data g; input g x @@; datalines;
1 1 1 2 1 4 2 . 2 .
;
%macro allm;
%do m = 1 %to 16;
  %let meth = %scan(mean median sum euclen ustd std range midrange maxabs iqr mad abw(4) ahuber(1) awave(2) agk(.5) spacing(.5), &m, %str( ));
  proc stdize data=g method=&meth pstat out=o; var x; by g; run;
  %show(M&m)
%end;
%mend;
%allm
data c; input x @@; datalines;
5 5 . 5 5
;
%macro cons;
%do m = 1 %to 9;
  %let meth = %scan(ustd midrange abw(4) ahuber(1) awave(2) agk(.5) spacing(.5) iqr std, &m, %str( ));
  proc stdize data=c method=&meth pstat out=o; var x; run;
  %show(K&m)
%end;
%mend;
%cons
data c0; input x @@; datalines;
0 0 0
;
proc stdize data=c0 method=maxabs pstat out=o; var x; run;
%show(K10)
proc stdize data=c0 method=euclen pstat out=o; var x; run;
%show(K11)
proc stdize data=c method=std replace out=o; var x; run;
%show(R1)
proc stdize data=c method=std missing=median out=o; var x; run;
%show(R2)
proc stdize data=c method=std reponly out=o; var x; run;
%show(R3)
proc stdize data=c method=std add=3 mult=2 missing=-1 out=o; var x; run;
%show(R4)
proc stdize data=c method=std missing=mean reponly out=o; var x; run;
%show(R5)
proc stdize data=c method=mean pstat out=o; var x; run;
%show(R6)
data g2; input g x @@; datalines;
1 1 1 2 2 . 2 . 3 7 3 .
;
proc stdize data=g2 method=std missing=-1 out=o; var x; by g; run;
%show(S1)
proc stdize data=g2 method=std replace out=o; var x; by g; run;
%show(S2)
proc stdize data=g2 method=std missing=median out=o; var x; by g; run;
%show(S3)
proc stdize data=g2 method=std reponly out=o; var x; by g; run;
%show(S4)
proc stdize data=g2 method=std missing=median reponly out=o; var x; by g; run;
%show(S5)
data z; input x @@; datalines;
1 1 1 1 9 .
;
proc stdize data=z method=mad pstat out=o; var x; run;
%show(Z1)
proc stdize data=z method=iqr missing=-1 out=o; var x; run;
%show(Z2)
data z2; input x @@; datalines;
-1 1 . 0
;
proc stdize data=z2 method=sum pstat out=o; var x; run;
%show(Z3)
proc stdize data=z2 method=std pstat out=o; var x; run;
%show(Z4)
data one; input g x y @@; datalines;
1 7 2 2 . 5 2 . 5 3 1 . 3 2 .
;
proc stdize data=one method=std pstat out=o; var x y; by g; run;
data _null_; set o; file print;
  if missing(x) then put 'B3 x missing'; else put 'B3 x ' x 14.9;
  if missing(y) then put 'B3 y missing'; else put 'B3 y ' y 14.9;
run;
proc stdize data=one method=abw(4) out=o; var x; by g; run;
%show(B1)
proc stdize data=one method=ahuber(1) out=o; var x; by g; run;
%show(B4)
proc stdize data=one method=spacing(.5) out=o; var x; by g; run;
%show(B5)
proc stdize data=one method=std nomiss out=o pstat; var x y; by g; run;
%show(B7)
data u; input x w @@; datalines;
1 1 2 2 3 0.5 4 3 5 1
;
proc stdize data=u method=ustd out=o pstat; var x; run;
%show(U1)
proc stdize data=u method=ustd vardef=wdf out=o; var x; weight w; run;
%show(U2)
proc stdize data=u method=ustd vardef=n out=o; var x; weight w; run;
%show(U3)
data f0; input x @@; datalines;
3 3 3 4
;
proc stdize data=f0 method=std fuzz=0.2 pstat out=o; var x; run;
%show(F1)
proc stdize data=f0 method=std fuzz=0.6 out=o; var x; run;
%show(F2)
data nm; input g x y @@; datalines;
1 1 2 1 2 4 1 3 . 1 5 7 3 1 . 3 2 .
;
proc stdize data=nm method=std nomiss out=o; var x y; by g; run;
data _null_; set o; file print;
  if missing(x) then put 'N1 x missing'; else put 'N1 x ' x 14.9;
  if missing(y) then put 'N1 y missing'; else put 'N1 y ' y 14.9;
run;
proc stdize data=nm method=std nomiss missing=-1 out=o; var x y; by g; run;
data _null_; set o; file print;
  if missing(x) then put 'N2 x missing'; else put 'N2 x ' x 14.9;
  if missing(y) then put 'N2 y missing'; else put 'N2 y ' y 14.9;
run;
proc stdize data=nm method=std nomiss reponly out=o; var x y; by g; run;
data _null_; set o; file print;
  if missing(x) then put 'N3 x missing'; else put 'N3 x ' x 14.9;
  if missing(y) then put 'N3 y missing'; else put 'N3 y ' y 14.9;
run;
proc stdize data=nm method=std nomiss replace out=o; var x y; by g; run;
data _null_; set o; file print;
  if missing(x) then put 'N4 x missing'; else put 'N4 x ' x 14.9;
  if missing(y) then put 'N4 y missing'; else put 'N4 y ' y 14.9;
run;
