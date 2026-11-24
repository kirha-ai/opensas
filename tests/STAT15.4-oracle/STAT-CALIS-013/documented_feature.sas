/* STAT-CALIS-013: CALIS — RAM / The RAM Model
 * Source: S154 / Chapter 33 / `RAM Statement` (PDF pp. 1643–1649); S154 / Chapter 33 / `The RAM Model` (PDF pp. 1720–1728).
 * Discriminates: Example 33.29: Fitting the RAM and EQS Models by the COSAN Modeling Language; explicit statements: RAM
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
proc calis nobs=932 data=Wheaton primat nose;
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
proc calis data=Wheaton nobs=932 nose;
cosan
var= Anomie67 Powerless67 Anomie71 Powerless71 Education SEI,
J(9, IDE) * A(9, GEN, IMI) * P(9, SYM);
matrix A
[1 2 8 , 7] = 1.0 0.833 beta,
[3 4 , 8] = 1.0 0.833 ,
[5 6 7 8 , 9] = 1. lambda gamma1 gamma2;
matrix P
[1,1] = theta1-theta2 theta1-theta4 ,
[7,7] = psi1 psi2 phi,
[3,1] = theta5 ,
[4,2] = theta5 ;
vnames
J = [Anomie67 Powerless67 Anomie71 Powerless71
Education SEI Alien67 Alien71 SES],
A = J,
P = A;
run;
proc calis nobs=932 data=Wheaton primat nose;
lineqs
Anomie67 = 1.0 * f_Alien67 + e1,
Powerless67 = 0.833 * f_Alien67 + e2,
Anomie71 = 1.0 * f_Alien71 + e3,
Powerless71 = 0.833 * f_Alien71 + e4,
Education = 1.0 * f_SES + e5,
SEI = lambda * f_SES + e6,
f_Alien67 = gamma1 * f_SES + d1,
f_Alien71 = gamma2 * f_SES + beta * f_Alien67 + d2;
variance
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
proc calis cov data=Wheaton nobs=932 nose;
cosan
var = Anomie67 Anomie71 Education Powerless67 Powerless71 SEI,
J(8, IDE) * Beta(8, GEN, IMI) * Gamma(9, GEN) * Phi(9, SYM);
matrix Beta
[1 4 8 , 7] = 1.0 0.833 beta,
[2 5 , 8] = 1.0 0.833 ;
matrix Gamma
[3 6 7 8 , 1] = 1.0 lambda gamma1 gamma2,
[1,2] = 8 * 1.0;
matrix Phi
[1,1] = phi 2*theta1 theta3 2*theta2 theta4 psi1 psi2,
[3,2] = theta5 ,
[6,5] = theta5 ;
vnames J = [Anomie67 Anomie71 Education Powerless67 Powerless71 SEI
f_Alien67 f_Alien71],
Beta = J,
Gamma = [f_SES e1 e3 e5 e2 e4 e6 d1 d2],
Phi = Gamma;
run;
run;
quit;
