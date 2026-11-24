/* STAT-PHREG-015: PHREG — ROC / Schemper-Henderson Predictive Measure / Concordance Statistics / Time-Dependent ROC Curves
 * Source: S154 / Chapter 92 / `ROC Statement` (PDF p. 7388); S154 / Chapter 92 / `Schemper-Henderson Predictive Measure` (PDF pp. 7429–7430); S154 / Chapter 92 / `Concordance Statistics` (PDF pp. 7434–7437); S154 / Chapter 92 / `Time-Dependent ROC Curves` (PDF pp. 7437–7441).
 * Discriminates: Example 92.7: Time-Dependent Repeated Measurements of a Covariate
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data Tumor;
infile datalines missover;
input ID Time Dead Dose P1-P15;
label ID='Subject ID';
datalines;
1 47 1 1.0 0 5 6 8 10 10 10 10
2 71 1 1.0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1
3 81 0 1.0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1
4 81 0 1.0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
5 81 0 1.0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
6 65 1 1.0 0 0 0 1 1 1 1 1 1 1 1 1 1
7 71 0 1.0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
8 69 0 1.0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
9 67 1 1.0 0 0 1 1 2 2 2 2 3 3 3 3 3 3
10 81 0 1.0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
11 37 1 1.0 9 9 9
12 81 0 1.0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
13 77 0 1.0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1
14 81 0 1.0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
15 81 0 1.0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
16 54 0 2.5 0 1 1 1 2 2 2 2 2 2 2 2
17 53 0 2.5 0 0 0 0 0 0 0 0 0 0 0 0
18 38 0 2.5 5 13 14
19 54 0 2.5 2 6 6 6 6 6 6 6 6 6 6 6
20 51 1 2.5 15 15 15 16 16 17 17 17 17 17 17
21 47 1 2.5 13 20 20 20 20 20 20 20
22 27 1 2.5 22
23 41 1 2.5 6 13 13 13
24 49 1 2.5 0 3 3 3 3 3 3 3 3
25 53 0 2.5 0 0 1 1 1 1 1 1 1 1 1 1
26 50 1 2.5 0 0 2 3 4 6 6 6 6 6
27 37 1 2.5 3 15 15
28 49 1 2.5 2 3 3 3 3 4 4 4 4
29 46 1 2.5 4 6 7 9 9 9 9
30 48 0 2.5 15 26 26 26 26 26 26 26
31 54 0 10.0 12 14 15 15 15 15 15 15 15 15 15 15
32 37 1 10.0 12 16 17
33 53 1 10.0 3 6 6 6 6 6 6 6 6 6 6 6
34 45 1 10.0 4 12 15 20 20 20
35 53 0 10.0 6 10 13 13 13 15 15 15 15 15 15 20
36 49 1 10.0 0 2 2 2 2 2 2 2 2
37 39 0 10.0 7 8 8
38 27 1 10.0 17
39 49 1 10.0 0 6 9 14 14 14 14 14 14
40 43 1 10.0 14 18 20 20 20
41 28 0 10.0 8
42 34 1 10.0 11 18
43 45 1 10.0 10 12 16 16 16 16
44 37 1 10.0 0 1 1
45 43 1 10.0 9 19 19 19 19
;
proc phreg data=Tumor;
model Time*Dead(0)=Dose NPap;
array pp{*} P1-P14;
array tt{*} t1-t15;
t1=27;
t2=34;
t3=37;
t4=41;
t5=43;
t6=45;
t7=46;
t8=47;
t9=49;
t10=50;
t11=51;
t12=53;
t13=65;
t14=67;
t15=71;
if Time < tt[1] then NPap=0;
else if time >= tt[15] then NPap=P15;
else do i=1 to dim(pp);
if tt[i] <= Time < tt[i+1] then NPap= pp[i];
end;
run;
data Tumor1(keep=ID Time Dead Dose T1 T2 NPap Status);
array pp{*} P1-P14;
array qq{*} P2-P15;
array tt{1:15} _temporary_
(27 34 37 41 43 45 46 47 49 50 51 53 65 67 71);
set Tumor;
T1 = 0;
T2 = 0;
Status = 0;
if ( Time = tt[1] ) then do;
T2 = tt[1];
NPap = p1;
Status = Dead;
output;
end;
else do _i_=1 to dim(pp);
if ( tt[_i_] = Time ) then do;
T2= Time;
NPap = pp[_i_];
Status = Dead;
output;
end;
else if (tt[_i_] < Time ) then do;
if (pp[_i_] ^= qq[_i_] ) then do;
if qq[_i_] = . then T2= Time;
else T2= tt[_i_];
NPap= pp[_i_];
Status= 0;
output;
T1 = T2;
end;
end;
end;
if ( Time >= tt[15] ) then do;
T2 = Time;
NPap = P15;
Status = Dead;
output;
end;
run;
proc phreg data=Tumor1 noprint;
model (T1,T2)*Status(0)=Dose NPap;
output out=Out1 resmart=Mart dfbeta=db1-db2;
id ID Time Dead;
run;
proc means data=Out1 noprint;
by ID Time Dead;
var Mart db1-db2;
output out=Out2 sum=Mart db_Dose db_NPap;
run;
title 'DfBetas for Dose';
proc sgplot data=Out2;
yaxis label="DfBeta" grid;
refline 0 / axis=y;
scatter y=db_Dose x=ID;
run;
title 'DfBetas for NPap';
proc sgplot data=Out2;
yaxis label="DfBeta" grid;
refline 0 / axis=y;
scatter y=db_NPap x=ID;
run;
