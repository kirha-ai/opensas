/* expect-rc: 1
 * STAT-STDIZE-001: PROC STDIZE rules settled with real SAS 9.4 runs on this
 * invented sample: REPLACE with ADD= (missing -> 0) and with MISSING=value or
 * MISSING=method (MISSING= wins); MISSING=method (that method's location
 * before standardizing, with REPONLY the location itself); WEIGHT ignored
 * (WARNING + NOTE) for RANGE/MIDRANGE/MAXABS; FREQ / NOTRUNCATE (0.5 used),
 * ignored with a WARNING for RANGE; NORM for IQR (IQR / 1.34898) and MAD
 * (MAD / 0.67449), ignored with a WARNING otherwise; SNORM WARNING; INITIAL=
 * NOTE; NMARKERS=, PCTLPTS=, UNSTD accepted and ignored; repeated VAR
 * statements accumulate, the first FREQ and the first WEIGHT are used, the
 * last repeated PROC option wins; an empty DATA= set (NOTEs, 0-observation OUT=, no PSTAT
 * table); the PSTAT Norm column is in stat_stdize001_norm.sas.
 * Expected values are the SAS outputs (printed there with 14.9). rc 1 comes
 * from the SAS WARNINGs.
 */
options nodate nonumber nocenter linesize=120;
data d;
input x y f w;
datalines;
1 4 1 1
2 . 1.5 2
3 8 2.7 0
6 . 1 1
10 3 0.5 3
;
proc stdize data=d out=p1 replace add=10; var x y; run;
data _null_; set p1; file print; put 'p1  ' x 14.9 y 14.9; run;
proc stdize data=d out=p2 replace missing=99; var x y; run;
data _null_; set p2; file print; put 'p2  ' x 14.9 y 14.9; run;
proc stdize data=d out=p3 method=range; var x y; weight w; run;
data _null_; set p3; file print; put 'p3  ' x 14.9 y 14.9; run;
proc stdize data=d out=p4 method=midrange; var x y; weight w; run;
data _null_; set p4; file print; put 'p4  ' x 14.9 y 14.9; run;
proc stdize data=d out=p5 method=maxabs; var x y; weight w; run;
data _null_; set p5; file print; put 'p5  ' x 14.9 y 14.9; run;
proc stdize data=d out=p6 method=mean; var x y; freq f / notruncate; run;
data _null_; set p6; file print; put 'p6  ' x 14.9 y 14.9; run;
proc stdize data=d out=p7 method=std; var x y; freq f / notrunc; run;
data _null_; set p7; file print; put 'p7  ' x 14.9 y 14.9; run;
proc stdize data=d out=p8 method=range; var x y; freq f / notruncate; run;
data _null_; set p8; file print; put 'p8  ' x 14.9 y 14.9; run;
proc stdize data=d out=p9 method=std missing=median; var x y; run;
data _null_; set p9; file print; put 'p9  ' x 14.9 y 14.9; run;
proc stdize data=d out=p10 method=std missing=mean reponly; var x y; run;
data _null_; set p10; file print; put 'p10 ' x 14.9 y 14.9; run;
proc stdize data=d out=p11 method=iqr norm; var x y; run;
data _null_; set p11; file print; put 'p11 ' x 14.9 y 14.9; run;
proc stdize data=d out=p12 method=mad norm; var x y; run;
data _null_; set p12; file print; put 'p12 ' x 14.9 y 14.9; run;
proc stdize data=d out=p13 method=std norm; var x y; run;
data _null_; set p13; file print; put 'p13 ' x 14.9 y 14.9; run;
proc stdize data=d out=p14 method=std snorm initial=mean nmarkers=10; var x y; run;
data _null_; set p14; file print; put 'p14 ' x 14.9 y 14.9; run;
proc stdize data=d out=p16 method=mean; var x y; freq f; freq w; run;
data _null_; set p16; file print; put 'p16 ' x 14.9 y 14.9; run;
proc stdize data=d out=p17 method=mean; var x y; weight f; weight w; run;
data _null_; set p17; file print; put 'p17 ' x 14.9 y 14.9; run;
proc stdize data=d out=p18 method=mean method=range; var x y; run;
data _null_; set p18; file print; put 'p18 ' x 14.9 y 14.9; run;
proc stdize data=d out=p19 method=std missing=range; var x y; run;
data _null_; set p19; file print; put 'p19 ' x 14.9 y 14.9; run;
proc stdize data=d out=p20 method=std missing=mean replace; var x y; run;
data _null_; set p20; file print; put 'p20 ' x 14.9 y 14.9; run;
proc stdize data=d out=p21 method=mean; var x y; weight w; freq f / notruncate; run;
data _null_; set p21; file print; put 'p21 ' x 14.9 y 14.9; run;
proc stdize data=d out=r1 method=std replace missing=median; var x y; run;
data _null_; set r1; file print; put 'r1  ' x 14.9 y 14.9; run;
proc stdize data=d out=r2 method=sum; var x y; freq f / notruncate; run;
data _null_; set r2; file print; put 'r2  ' x 14.9 y 14.9; run;
proc stdize data=d out=r4 unstd; var x y; run;
data _null_; set r4; file print; put 'r4  ' x 14.9 y 14.9; run;
proc stdize data=d out=r5 add=1 add=5 mult=3 mult=2; var x y; run;
data _null_; set r5; file print; put 'r5  ' x 14.9 y 14.9; run;
proc stdize data=d out=r7 method=std reponly missing=range; var x y; run;
data _null_; set r7; file print; put 'r7  ' x 14.9 y 14.9; run;
proc stdize data=d out=r8 method=iqr norm reponly; var x y; run;
data _null_; set r8; file print; put 'r8  ' x 14.9 y 14.9; run;
proc stdize data=d out=q5 pctlpts=10, 30 nmarkers=3; var x; run;
data _null_; set q5; file print; put 'q5  ' x 14.9; run;
/* MISSING= RANGE / METHOD= RANGE make the whole step ignore WEIGHT and
 * NOTRUNCATE (SAS-verified). */
proc stdize data=d out=t1 method=std missing=range; var x y; weight w; run;
proc stdize data=d out=t2 method=range missing=mean; var x y; weight w; run;
proc stdize data=d out=t3 method=std missing=range; var x y; freq f / notruncate; run;
proc stdize data=d out=t4 method=range missing=mean; var x y; freq f / notruncate; run;
proc stdize data=d out=t5 method=range missing=mean reponly; var x y; weight w; run;
data all; merge t1(rename=(y=y1)) t2(rename=(y=y2)) t3(rename=(y=y3)) t4(rename=(y=y4)) t5(rename=(y=y5)); keep y1-y5; run;
data _null_; set all; file print; put 't   ' (y1-y5) (14.9); run;
data e; set d; stop; run;
proc stdize data=e out=q3 pstat; var x y; run;
