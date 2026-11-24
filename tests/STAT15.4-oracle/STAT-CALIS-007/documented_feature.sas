/* STAT-CALIS-007: CALIS — COSAN / The COSAN Model
 * Source: S154 / Chapter 33 / `COSAN Statement` (PDF pp. 1534–1544); S154 / Chapter 33 / `The COSAN Model` (PDF pp. 1685–1689).
 * Discriminates: Example 33.31: Linear Relations among Factor Loadings: COSAN Model Specification; explicit statements: COSAN
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
length _name_ $32 _type_ $8;
infile datalines truncover;

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
[ ,1] = b11 b21 b31 b41 b51 b61,
[ ,2] = b12 b22 b32 b42 b52 b62;
matrix Psi
[1,1] = psi1-psi6;
matrix D
[1,1] = d1-d6;
parameters alpha (1.);
/* SAS Programming Statements to Define Dependent Parameters*/
/* 6 constraints on the factor loadings */
b12 = alpha - b11;
b22 = alpha - b21;
b32 = alpha - b31;
b42 = alpha - b41;
b52 = alpha - b51;
b62 = alpha - b61;
/* 6 Constraints on Correlation structures */
psi1 = 1. - b11 * b11 - b12 * b12;
psi2 = 1. - b21 * b21 - b22 * b22;
psi3 = 1. - b31 * b31 - b32 * b32;
psi4 = 1. - b41 * b41 - b42 * b42;
psi5 = 1. - b51 * b51 - b52 * b52;
psi6 = 1. - b61 * b61 - b62 * b62;
vnames
D = [var1-var6],
B = [factor1 factor2],
Psi = D;
run;
run;
quit;
