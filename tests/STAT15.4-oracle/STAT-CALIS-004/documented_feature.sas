/* STAT-CALIS-004: CALIS — COV / MEAN / PCOV / PVAR / STD / VARIANCE
 * Source: S154 / Chapter 33 / `COV Statement` (PDF pp. 1544–1549); S154 / Chapter 33 / `MEAN Statement` (PDF pp. 1602–1605); S154 / Chapter 33 / `PCOV Statement` (PDF pp. 1638–1641); S154 / Chapter 33 / `PVAR Statement` (PDF pp. 1641–1643); S154 / Chapter 33 / `STD Statement` (PDF p. 1653); S154 / Chapter 33 / `VARIANCE Statement` (PDF pp. 1657–1661).
 * Discriminates: Example 33.11: Measurement Error Models Specified as Linear Equations; explicit statements: COV, MEAN, PCOV, PVAR, VARIANCE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data measures;
input x y @@;
datalines;
7.91736 13.8673 6.10807 11.7966 6.94139 12.2174
7.61290 12.9761 6.77190 11.6356 6.33328 11.7732
7.60608 12.8040 6.65642 12.8866 6.26643 11.9382
7.32266 13.2590 5.76977 10.7654 5.62881 11.5041
7.57418 13.2502 7.17305 13.3416 8.23123 13.9876
7.17199 13.1750 8.04604 14.5968 5.77692 11.5077
5.72741 11.3299 6.66033 12.5159 7.14944 12.4988
7.51832 12.3588 5.48877 11.2211 7.50323 13.3735
7.15814 13.1556 7.35485 13.8457 8.91648 14.4929
5.37445 9.6366 6.00419 11.7654 6.89546 13.1493
;
run;
data multiple(type=cov);
length _name_ $32 _type_ $8;
infile datalines truncover;

input _type_ :$8. _name_ :$32. y x1 x2 x3;
datalines;
mean . 0.93 1.33 1.34 4.11
cov y 1.31 . . .
cov x1 1.24 1.42 . .
cov x2 0.21 0.18 1.15 .
cov x3 3.91 4.21 0.58 14.11
;
run;
proc calis data=measures;
path
x <=== Fx = 1.,
Fx ===> Fy ,
Fy ===> y = 1.;
pvar
x = 0.019,
y = 0.022,
Fx Fy;
run;
proc calis data=measures;
lineqs
x = 1. * Fx + e1,
y = 1. * Fy + e2,
Fy = * Fx + d;
variance
e1 = 0.019,
e2 = 0.022,
Fx d;
run;
proc calis data=multiple nobs=37;
path
Fy <=== F1 F2 F3,
F1 ===> x1 = 1.,
F2 ===> x2 = 1.,
F3 ===> x3 = 1.,
Fy ===> y = 1.;
pvar
x1 x2 x3 y = .02 .03 .15 .02,
Fy;
pcov
x1 x2 = 0.01;
run;
proc calis data=multiple nobs=37;
lineqs
Fy = * F1 + * F2 + * F3 + d,
x1 = 1. * F1 + e1,
x2 = 1. * F2 + e2,
x3 = 1. * F3 + e3,
y = 1. * Fy + ey;
variance
e1-e3 ey = .02 .03 .15 .02,
d;
cov
e1 e2 = 0.01;
run;
