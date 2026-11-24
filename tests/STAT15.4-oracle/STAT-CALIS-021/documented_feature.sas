/* STAT-CALIS-021: CALIS — Automatic Variable Selection
 * Source: S154 / Chapter 33 / `Automatic Variable Selection` (PDF pp. 1734–1735).
 * Discriminates: Getting Started: CALIS Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Wheaton(TYPE=COV);
length _name_ $32 _type_ $8;
infile datalines truncover;

_type_ = 'cov';
input _name_ :$32. Anomie67 Powerless67 Anomie71 Powerless71
Education SEI;
label Anomie67='Anomie (1967)' Powerless67='Powerlessness (1967)'
Anomie71='Anomie (1971)' Powerless71='Powerlessness (1971)'
Education='Education' SEI='Occupational Status Index';
datalines;
Anomie67 11.834 . . . . .
Powerless67 6.947 9.364 . . . .
Anomie71 6.819 5.091 12.532 . . .
Powerless71 4.783 5.028 7.495 9.986 . .
Education -3.839 -3.889 -3.841 -3.625 9.610 .
SEI -21.899 -18.831 -21.748 -18.775 35.522 450.288
;
run;
proc calis nobs=932 data=Wheaton;
path
Anomie67 <=== Alien67 = 1.0,
Powerless67 <=== Alien67 = 0.833,
Anomie71 <=== Alien71 = 1.0,
Powerless71 <=== Alien71 = 0.833,
Education <=== SES = 1.0,
SEI <=== SES = lambda,
Alien67 <=== SES = gamma1,
Alien71 <=== SES = gamma2,
Alien71 <=== Alien67 = beta;
pvar
Anomie67 = theta1,
Powerless67 = theta2,
Anomie71 = theta1,
Powerless71 = theta2,
Education = theta3,
SEI = theta4,
Alien67 = psi1,
Alien71 = psi2,
SES = phi;
pcov
Anomie67 Anomie71 = theta5,
Powerless67 Powerless71 = theta5;
run;
proc calis nobs=932 data=Wheaton;
ram
var = Anomie67 /* 1 */
Powerless67 /* 2 */
Anomie71 /* 3 */
Powerless71 /* 4 */
Education /* 5 */
SEI /* 6 */
Alien67 /* 7 */
Alien71 /* 8 */
SES, /* 9 */
_A_ 1 7 1.0,
_A_ 2 7 0.833,
_A_ 3 8 1.0,
_A_ 4 8 0.833,
_A_ 5 9 1.0,
_A_ 6 9 lambda,
_A_ 7 9 gamma1,
_A_ 8 9 gamma2,
_A_ 8 7 beta,
_P_ 1 1 theta1,
_P_ 2 2 theta2,
_P_ 3 3 theta1,
_P_ 4 4 theta2,
_P_ 5 5 theta3,
_P_ 6 6 theta4,
_P_ 7 7 psi1,
_P_ 8 8 psi2,
_P_ 9 9 phi,
_P_ 1 3 theta5,
_P_ 2 4 theta5;
run;
proc calis nobs=932 data=Wheaton;
lineqs
Anomie67 = 1.0 * f_Alien67 + E1,
Powerless67 = 0.833 * f_Alien67 + E2,
Anomie71 = 1.0 * f_Alien71 + E3,
Powerless71 = 0.833 * f_Alien71 + E4,
Education = 1.0 * f_SES + E5,
SEI = lambda * f_SES + E6,
f_Alien67 = gamma1 * f_SES + D1,
f_Alien71 = gamma2 * f_SES + beta * f_Alien67 + D2;
std
E1 = theta1,
E2 = theta2,
E3 = theta1,
E4 = theta2,
E5 = theta3,
E6 = theta4,
D1 = psi1,
D2 = psi2,
f_SES = phi;
cov
E1 E3 = theta5,
E2 E4 = theta5;
run;
proc calis nobs=932 data=Wheaton;
lismod
yvar = Anomie67 Powerless67 Anomie71 Powerless71,
xvar = Education SEI,
etav = Alien67 Alien71,
xiv = SES;
matrix _LAMBDAY_ [1,1] = 1.0,
[2,1] = 0.833,
[3,2] = 1.0,
[4,2] = 0.833;
matrix _LAMBDAX_ [1,1] = 1.0,
[2,1] = lambda;
matrix _GAMMA_ [1,1] = gamma1,
[2,1] = gamma2;
matrix _BETA_ [2,1] = beta;
matrix _THETAY_ [1,1] = theta1,
[2,2] = theta2,
[3,3] = theta1,
[4,4] = theta2,
[3,1] = theta5,
[4,2] = theta5;
matrix _THETAX_ [1,1] = theta3,
[2,2] = theta4;
matrix _PSI_ [1,1] = psi1,
[2,2] = psi2;
matrix _PHI_ [1,1] = phi;
run;
proc calis nobs=932 data=Wheaton corr;
factor n=2 rotate=varimax;
run;
proc factor nobs=932 data=Wheaton n=2 rotate=varimax method=ml;
run;
proc calis nobs=932 data=Wheaton;
factor
Alien67 ===> Anomie67 Powerless67 = 1.0 load1,
Alien71 ===> Anomie71 Powerless71 = 1.0 load2,
SES ===> Education SEI = 1.0 load3;
pvar
Alien67 = phi11,
Alien71 = phi22,
SES = phi33,
Anomie67 = theta1,
Powerless67 = theta2,
Anomie71 = theta3,
Powerless71 = theta4,
Education = theta5,
SEI = theta6;
cov
Alien71 Alien67 = phi21,
SES Alien67 = phi31,
SES Alien71 = phi32;
run;
proc calis nobs=932 data=Wheaton;
mstruct
var = Anomie67 Powerless67 Anomie71 Powerless71;
matrix _COV_ [1,1] = phi1,
[2,2] = phi2,
[3,3] = phi1,
[4,4] = phi2,
[2,1] = theta1,
[3,1] = theta2,
[3,2] = theta1,
[4,1] = theta1,
[4,2] = theta3,
[4,3] = theta1;
run;
run;
quit;
