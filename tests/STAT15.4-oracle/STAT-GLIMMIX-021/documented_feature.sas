/* STAT-GLIMMIX-021: GLIMMIX — LSMEANS / LSMESTIMATE / SLICE
 * Source: S154 / Chapter 52 / `LSMEANS Statement` (PDF pp. 3751–3764); S154 / Chapter 52 / `LSMESTIMATE Statement` (PDF pp. 3764–3772); S154 / Chapter 52 / `SLICE Statement` (PDF p. 3817).
 * Discriminates: Example 52.17: Linear Inference Based on Summary Data; explicit statements: LSMEANS, LSMESTIMATE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data theop;
input time dose conc @@;
if (dose = 4) then group=1;
else group=2;
datalines;
0.00 4 0.1633 0.25 4 2.045
0.27 4 4.4 0.30 4 7.37
0.35 4 1.89 0.37 4 2.89
0.50 4 3.96 0.57 4 6.57
0.58 4 6.9 0.60 4 4.6
0.63 4 9.03 0.77 4 5.22
1.00 4 7.82 1.02 4 7.305
1.05 4 7.14 1.07 4 8.6
1.12 4 10.5 2.00 4 9.72
2.02 4 7.93 2.05 4 7.83
2.13 4 8.38 3.50 4 7.54
3.52 4 9.75 3.53 4 5.66
3.55 4 10.21 3.62 4 7.5
3.82 4 8.58 5.02 4 6.275
5.05 4 9.18 5.07 4 8.57
5.08 4 6.2 5.10 4 8.36
7.02 4 5.78 7.03 4 7.47
7.07 4 5.945 7.08 4 8.02
7.17 4 4.24 8.80 4 4.11
9.00 4 4.9 9.02 4 5.33
9.03 4 6.11 9.05 4 6.89
9.38 4 7.14 11.60 4 3.16
11.98 4 4.19 12.05 4 4.57
12.10 4 5.68 12.12 4 5.94
12.15 4 3.7 23.70 4 2.42
24.15 4 1.17 24.17 4 1.05
24.37 4 3.28 24.43 4 1.12
24.65 4 1.15 0.00 5 0.025
0.25 5 2.92 0.27 5 1.505
0.30 5 2.02 0.50 5 4.795
0.52 5 5.53 0.58 5 3.08
0.98 5 7.655 1.00 5 9.855
1.02 5 5.02 1.15 5 6.44
1.92 5 8.33 1.98 5 6.81
2.02 5 7.8233 2.03 5 6.32
3.48 5 7.09 3.50 5 7.795
3.53 5 6.59 3.57 5 5.53
3.60 5 5.87 5.00 5 5.8
5.02 5 6.2867 5.05 5 5.88
6.98 5 5.25 7.00 5 4.02
7.02 5 7.09 7.03 5 4.925
7.15 5 4.73 9.00 5 4.47
9.03 5 3.62 9.07 5 4.57
9.10 5 5.9 9.22 5 3.46
12.00 5 3.69 12.05 5 3.53
12.10 5 2.89 12.12 5 2.69
23.85 5 0.92 24.08 5 0.86
24.12 5 1.25 24.22 5 1.15
24.30 5 0.9 24.35 5 1.57
;
proc nlin data=theop outest=cov;
parms beta1_1=-3.22 beta2_1=0.47 beta3_1=-2.45
beta1_2=-3.22 beta2_2=0.47 beta3_2=-2.45;
if (group=1) then do;
cl = exp(beta1_1);
ka = exp(beta2_1);
ke = exp(beta3_1);
end;
else do;
cl = exp(beta1_2);
ka = exp(beta2_2);
ke = exp(beta3_2);
end;
mean = dose*ke*ka*(exp(-ke*time)-exp(-ka*time))/cl/(ka-ke);
model conc = mean;
ods output ParameterEstimates=ests;
run;
data covb;
set cov(where=(_type_='COVB'));
rename beta1_1=col1 beta2_1=col2 beta3_1=col3
beta1_2=col4 beta2_2=col5 beta3_2=col6;
row = _n_;
Parm = 1;
keep parm row beta:;
run;
proc print data=covb;
run;
proc glimmix data=ests order=data;
class Parameter;
model Estimate = Parameter / noint df=92 s;
random _residual_ / type=lin(1) ldata=covb v;
parms (1) / noiter;
lsmeans parameter / cl;
lsmestimate Parameter
'beta1 eq. across groups' 1 0 0 -1,
'beta2 eq. across groups' 0 1 0 0 -1,
'beta3 eq. across groups' 0 0 1 0 0 -1 /
adjust=bon stepdown ftest(label='Homogeneity');
run;
data pdata;
set covb;
array col{6};
do i=1 to _n_;
estimate=col{i}; output;
end;
keep estimate;
run;
quit;
