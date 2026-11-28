/* expect-rc: 1
 * STAT-SIMNORMAL-001: documented and SAS 9.4-verified invalid inputs of PROC SIMNORMAL.
 * Invented moments. Expected messages are the SAS 9.4 log of the same steps. */
options nosyntaxcheck nocenter nodate nonumber linesize=120;
data scov(type=cov);
length _TYPE_ $8 _NAME_ $8;
input _TYPE_ $ _NAME_ $ s1 s2;
datalines;
COV s1 1.915 0.3873
COV s2 0.3873 4.321
MEAN . 1.305 2.003
;
run;
data ch(type=cov); length _TYPE_ $8 _NAME_ $8 c $4; input _TYPE_ $ _NAME_ $ s1 s2 c $;
datalines;
COV s1 1 0 a
COV s2 0 1 b
MEAN . 0 0 c
;
run;
proc simnorm data=ch out=e1 nr=2 seed=1; var s1 c; run;
proc simnorm data=scov out=e2 nr=2 seed=1; var s1 zz; run;
data npd(type=cov); length _TYPE_ $8 _NAME_ $8; input _TYPE_ $ _NAME_ $ s1 s2;
datalines;
COV s1 1 2
COV s2 2 1
MEAN . 0 0
;
run;
proc simnorm data=npd out=e3 nr=2 seed=1; var s1 s2; run;
data mis(type=cov); length _TYPE_ $8 _NAME_ $8; input _TYPE_ $ _NAME_ $ s1 s2;
datalines;
COV s1 1 .
COV s2 . 1
MEAN . 0 .
;
run;
proc simnorm data=mis out=e4 nr=2 seed=1; var s1 s2; run;
proc simnorm data=scov out=e6 nr=-1 seed=1; var s1 s2; run;
proc simnorm data=scov out=e12 nr=2 seed=1 singular1=2; var s1 s2; run;
proc simnorm data=scov out=e13 nr=2 seed=1 bogus=3; var s1 s2; run;
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
proc simnorm data=scovb out=e15 nr=2 seed=1; by descending g; var s1 s2; run;
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
data emp(type=cov); set c3; stop; run;
proc simnormal data=emp out=r2 nr=3 seed=987; var a b; run;
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
proc simnormal data=bg out=r3 nr=1 seed=987; by g; var a b; run;
data ci(type=corr); length _TYPE_ $8 _NAME_ $8; input _TYPE_ $ _NAME_ $ a b;
datalines;
STD . 1 2
CORR a 1 .
CORR b . 1
;
run;
proc simnormal data=ci out=r6 nr=1 seed=987; var a b; run;
proc simnormal data=c3 out=r8 nr=1 seed=987; var a a b; run;
proc simnormal data=bg out=r9 nr=1 seed=987; by g; var g a; run;
proc simnormal data=c3 out=r10 nr=2 seed=987; run;
data asy(type=cov); length _TYPE_ $8 _NAME_ $8; input _TYPE_ $ _NAME_ $ a b;
datalines;
COV a 1 0.5
COV b 0.4 1
;
run;
proc simnormal data=asy out=r15 nr=1 seed=987; var a b; run;
data mr(type=cov); length _TYPE_ $8 _NAME_ $8; input _TYPE_ $ _NAME_ $ a b;
datalines;
COV a 1 0.5
MEAN . 0 0
;
run;
proc simnormal data=mr out=r14 nr=1 seed=987; var a b; run;
proc simnormal data=c3 out=r23 nr=1 seed=987; by g; var a b; run;
data _null_;
  file print;
  set r3 nobs=n;
  put 'r3 ' n= g= a= b= rnum=;
run;
