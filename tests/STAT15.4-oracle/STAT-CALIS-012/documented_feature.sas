/* STAT-CALIS-012: CALIS — PATH / The PATH Model
 * Source: S154 / Chapter 33 / `PATH Statement` (PDF pp. 1616–1626); S154 / Chapter 33 / `The PATH Model` (PDF pp. 1714–1720).
 * Discriminates: Example 33.17: Path Analysis: Stability of Alienation; explicit statements: PATH
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title "Stability of Alienation";
title2 "Data Matrix of WHEATON, MUTHEN, ALWIN & SUMMERS (1977)";
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
Education   -3.839 -3.889 -3.841 -3.625 9.610 .
SEI         -21.899 -18.831 -21.748 -18.775 35.522 450.288
;
ods graphics on;
proc calis nobs=932 data=Wheaton plots=residuals;
path
Anomie67 Powerless67 <=== Alien67 = 1.0 0.833,
Anomie71 Powerless71 <=== Alien71 = 1.0 0.833,
Education SEI <=== SES = 1.0 lambda,
Alien67 Alien71 <=== SES = gamma1 gamma2,
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
pathdiagram title='Stability of Alienation';
run;
ods graphics off;
run;
quit;
