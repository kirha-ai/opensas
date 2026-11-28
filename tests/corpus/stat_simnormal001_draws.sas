/* expect-rc: 0 */
/* STAT-SIMNORMAL-001: PROC SIMNORMAL draws, options, VAR/BY roles and OUT= layout.
 * Invented moments. Expected rows are SAS 9.4 output of this program (best16.).
 * Stream: classic RANNOR generator from SEED=, two uniforms per N(0,1) component. */
options nocenter nodate nonumber linesize=120;
data scov(type=cov);
length _TYPE_ $8 _NAME_ $8;
input _TYPE_ $ _NAME_ $ s1 s2;
datalines;
COV s1 1.915 0.3873
COV s2 0.3873 4.321
MEAN . 1.305 2.003
;
run;
data scovb(type=cov);
length _TYPE_ $8 _NAME_ $8;
input g _TYPE_ $ _NAME_ $ s1 s2;
datalines;
1 COV s1 1 0
1 COV s2 0 1
1 MEAN . 0 0
2 COV s1 1 0
2 COV s2 0 1
2 MEAN . 0 0
;
run;
data sc(type=corr);
length _TYPE_ $8 _NAME_ $8;
input _TYPE_ $ _NAME_ $ s1 s2;
datalines;
STD . 2 3
N . 10 10
CORR s2 0.5 1
CORR s1 1 0.5
;
run;
data c3(type=cov);
length _TYPE_ $8 _NAME_ $8;
input _TYPE_ $ _NAME_ $ a b c;
datalines;
N . 20 20 20
MEAN . 10 -2 0.5
COV a 4 1.2 -0.6
COV b 1.2 9 2.1
COV c -0.6 2.1 1.5
;
run;
data bg(type=cov); length _TYPE_ $8 _NAME_ $8;
input g _TYPE_ $ _NAME_ $ a b;
datalines;
1 COV a 1 0
1 COV b 0 1
1 MEAN . 5 5
2 MEAN . 7 7
3 COV a 1 0
3 COV b 0 1
;
run;
data sg(type=cov); length _TYPE_ $8 _NAME_ $8; input _TYPE_ $ _NAME_ $ a b;
datalines;
cov a 1 1
cov b 1 1
mean . 0 0
;
run;
data zz(type=cov); length _TYPE_ $8 _NAME_ $8; input _TYPE_ $ _NAME_ $ a b;
datalines;
COV a 0 0
COV b 0 1
;
run;
data cn(type=corr); length _TYPE_ $8 _NAME_ $8; input _TYPE_ $ _NAME_ $ a b;
datalines;
MEAN . 1 2
CORR a 1 0.5
CORR b 0.5 1
;
run;
proc simnorm data=scov outsim=a2 numreal=4 seed=54321 outseed; var s1 s2; run;
proc simnorm data=scovb out=a3 nr=2 seed=54321; by g; var s1 s2; run;
proc simnorm data=scovb out=a4 numr=2 seed=54321 seedby outseed; by g; var s1 s2; run;
proc simnorm data=sc out=a5 nr=2 seed=54321; var s2 s1; run;
proc simnormal data=c3 out=r1 nr=3 seed=987; var c a b; run;
proc simnormal data=sg out=r16 nr=2 seed=987; var a b; run;
proc simnormal data=zz out=r17 nr=2 seed=987; var a b; run;
proc simnormal data=cn out=r5 nr=1 seed=987; var a b; run;
proc simnormal data=scov out=e7 nr=2.5 seed=1; var s1 s2; run;
proc simnormal data=scov out=e11 nr=5 nr=2 seed=54321 seed=1; var s1 s2; run;
proc simnormal data=bg(where=(g=1)) out=r7 nr=1 seed=987; var a b; run;
proc simnormal data=bg out=r7b nr=1 seed=987; where g=3; by g; var a b; run;
proc simnormal data=c3 out=r13(keep=a rnum) nr=1 seed=987; var a b; run;
proc simnormal data=c3 out=r19 nr=1 seed=987 data=bg; var a b; run;
proc simnormal data=c3 out=r20 out=r21 nr=1 seed=987 sing1=0 outcond; var a; var b; run;
proc simnormal data=scov out=e5 nr=0 seed=1; var s1 s2; run;
proc simnormal data=scov seed=54321; var s1 s2; run;
%macro show(ds);
title "&ds";
proc print data=&ds(obs=4); format _numeric_ best16.; run;
%mend;
%show(a2) %show(a3) %show(a4) %show(a5) %show(r1) %show(r16) %show(r17) %show(r5)
%show(e7) %show(e11) %show(r7) %show(r7b) %show(r13) %show(r19) %show(r20) %show(data1)
