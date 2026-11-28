/* STAT-INBREED-001: PROC INBREED on a five-animal pedigree (founders A, B;
   full sibs C, D; E = C x D). COVAR MATRIX is the reference case; MATRIX IND
   (inbreeding mode) and COVAR IND INIT=0 were checked against a SAS 9.4
   reference run. Hand mathematics: f_AC = (f_AA + f_AB)/2 = 1/4,
   f_CD = 1/4, f_CE = 3/8, F_E = f_CD = 1/4; unrelated founders have a
   missing (".") coancestry, also with INIT=0. Data: invented. */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
data pedigree;
input animal $ sire $ dam $;
datalines;
A . .
B . .
C A B
D A B
E C D
;
run;
proc inbreed data=pedigree covar matrix;
var animal sire dam;
run;
proc inbreed data=pedigree matrix ind;
var animal sire dam;
run;
proc inbreed data=pedigree covar ind init=0;
var animal sire dam;
run;
proc inbreed data=pedigree;
run;
