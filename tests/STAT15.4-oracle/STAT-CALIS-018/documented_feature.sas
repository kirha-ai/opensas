/* STAT-CALIS-018: CALIS — BOUNDS / LINCON / NLINCON
 * Source: S154 / Chapter 33 / `BOUNDS Statement` (PDF pp. 1533–1534); S154 / Chapter 33 / `LINCON Statement` (PDF pp. 1568–1569); S154 / Chapter 33 / `NLINCON Statement` (PDF p. 1610).
 * Discriminates: Example 33.32: Ordinal Relations among Factor Loadings; explicit statements: LINCON
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data kinzer(type=corr);
title "Data Matrix of Kinzer & Kinzer, see GUTTMAN (1957)";
_type_ = 'corr';
input _name_ $ var1-var6;
datalines;
var1 1.00 . . . . .
var2 .51 1.00 . . . .
var3 .46 .51 1.00 . . .

var4 .46 .47 .54 1.00 . .
var5 .40 .39 .49 .57 1.00 .
var6 .33 .39 .47 .45 .56 1.00
;

run;

proc calis data=Kinzer nobs=326 nose;
cosan
var= var1-var6,
D(6,DIA) * B(2,GEN) + D(6,DIA) * Psi(6,DIA);
matrix B
[ ,1]= b11 b21 b31 b41 b51 b61,
[ ,2]= 0. b22 b32 b42 b52 b62;
matrix Psi
[1,1]= psi1-psi6;
matrix D
[1,1]= d1-d6 ;
lincon
b61 <= b51,
b51 <= b41,
b41 <= b31,
b31 <= b21,
b21 <= b11,
0. <= b22,
b22 <= b32,
b32 <= b42,
b42 <= b52,
b52 <= b62;
/* SAS Programming Statements */
/* 6 Constraints on Correlation structures */
psi1 = 1. - b11 * b11;
psi2 = 1. - b21 * b21 - b22 * b22;
psi3 = 1. - b31 * b31 - b32 * b32;
psi4 = 1. - b41 * b41 - b42 * b42;
psi5 = 1. - b51 * b51 - b52 * b52;
psi6 = 1. - b61 * b61 - b62 * b62;
vnames
B = [factor1 factor2],
Psi = [var1-var6],
D = Psi;
run;
