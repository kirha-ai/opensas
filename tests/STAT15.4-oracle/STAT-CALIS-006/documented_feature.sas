/* STAT-CALIS-006: CALIS — MODEL / Default Analysis Type and Default Parameterization / Naming Variables and Parameters
 * Source: S154 / Chapter 33 / `MODEL Statement` (PDF pp. 1605–1607); S154 / Chapter 33 / `Default Analysis Type and Default Parameterization` (PDF pp. 1683–1685); S154 / Chapter 33 / `Naming Variables and Parameters` (PDF pp. 1728–1729).
 * Discriminates: Example 33.33: Longitudinal Factor Analysis; explicit statements: MODEL
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

Title "Swaminathan's Longitudinal Factor Model, Data: McDONALD(1980)";
Title2 "Constructed Singular Correlation Matrix, GLS & ML not possible";
data Mcdon(TYPE=CORR);
length _name_ $32 _type_ $8;
infile datalines truncover;

_TYPE_ = 'CORR';
INPUT _NAME_ $ obs1-obs9;
datalines;
obs1 1.000 . . . . . . . .
obs2 .100 1.000 . . . . . . .
obs3 .250 .400 1.000 . . . . . .
obs4 .720 .108 .270 1.000 . . . . .
obs5 .135 .740 .380 .180 1.000 . . . .
obs6 .270 .318 .800 .360 .530 1.000 . . .
obs7 .650 .054 .135 .730 .090 .180 1.000 . .
obs8 .108 .690 .196 .144 .700 .269 .200 1.000 .
obs9 .189 .202 .710 .252 .336 .760 .350 .580 1.000
;
proc calis data=Mcdon method=ls nobs=100 corr;
cosan
var = obs1-obs9,
F1(6,GEN) * F2(6,DIA) * F3(6,DIA) * L(6,LOW) * F3(6,DIA,INV)
* F2(6,DIA,INV) * P(6,DIA) + U(9,SYM);
matrix F1
[1 , @1] = x1-x3,
[2 , @2] = x4-x5,
[4 , @3] = x6-x8,
[5 , @4] = x9-x10,
[7 , @5] = x11-x13,
[8 , @6] = x14-x15;
matrix F2
[1,1]= 2 * 1. x16 x17 x16 x17;
matrix F3
[1,1]= 4 * 1. x18 x19;
matrix L
[1,1]= 6 * 1.,
[3,1]= 4 * 1.,
[5,1]= 2 * 1.;
matrix P
[1,1]= 2 * 1. x20-x23;
matrix U
[1,1]= x24-x32,
[4,1]= x33-x38,
[7,1]= x39-x41;
bounds 0. <= x24-x32,
-1. <= x16-x19 <= 1.;
/* SAS programming statements for dependent parameters */
x20 = 1. - x16 * x16;
x21 = 1. - x17 * x17;
x22 = 1. - x18 * x18;
x23 = 1. - x19 * x19;
run;
run;
quit;
