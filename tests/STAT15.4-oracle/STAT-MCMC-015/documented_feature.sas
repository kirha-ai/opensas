/* STAT-MCMC-015: MCMC — Initial Values of the Markov Chains / Matrix Functions in PROC MCMC / Autocall Macros for Postprocessing
 * Source: S154 / Chapter 80 / `Initial Values of the Markov Chains` (PDF pp. 6156–6157); S154 / Chapter 80 / `Matrix Functions in PROC MCMC` (PDF pp. 6182–6186); S154 / Chapter 80 / `Autocall Macros for Postprocessing` (PDF pp. 6212–6215).
 * Discriminates: Getting Started: MCMC Procedure
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods graphics on;
proc mcmc data=sashelp.class outpost=classout nmc=1000 thin=2 seed=246810 nbi=200;
parms beta0 0 beta1 0;
parms sigma2 1;
prior beta0 beta1 ~ normal(mean = 0, var = 1e6);
prior sigma2 ~ igamma(shape = 3/10, scale = 10/3);
mu = beta0 + beta1*height;
model weight ~ n(mu, var = sigma2);
run;
ods graphics off;
title 'The Behrens-Fisher Problem';
data behrens;
input y ind @@;
datalines;
121 1 94 1 119 1 122 1 142 1 168 1 116 1
172 1 155 1 107 1 180 1 119 1 157 1 101 1
145 1 148 1 120 1 147 1 125 1 126 2 125 2
130 2 130 2 122 2 118 2 118 2 111 2 123 2
126 2 127 2 111 2 112 2 121 2
;
proc mcmc data=behrens outpost=postout seed=123
nmc=1000 monitor=(_parms_ mudif)
statistics(alpha=0.01) nbi=200;
ods select PostSumInt;
parm mu1 0 mu2 0;
parm sig21 1;
parm sig22 1;
prior mu: ~ general(0);
prior sig21 ~ general(-log(sig21), lower=0);
prior sig22 ~ general(-log(sig22), lower=0);
mudif = mu1 - mu2;
if ind = 1 then do;
mu = mu1;
s2 = sig21;
end;
else do;
mu = mu2;
s2 = sig22;
end;
model y ~ normal(mu, var=s2);
run;
proc format;
value diffmt low-0 = 'mu1 - mu2 <= 0' 0<-high = 'mu1 - mu2 > 0';
run;
proc freq data = postout;
tables mudif /nocum;
format mudif diffmt.;
run;
title 'Random-Effects Model';
data heights;
input Family G$ Height @@;
datalines;
1 F 67 1 F 66 1 F 64 1 M 71 1 M 72 2 F 63
2 F 63 2 F 67 2 M 69 2 M 68 2 M 70 3 F 63
3 M 64 4 F 67 4 F 66 4 M 67 4 M 67 4 M 69
;
data input;
set heights;
if g eq 'F' then gf = 1;
else gf = 0;
drop g;
run;
ods graphics on;
proc mcmc data=input outpost=postout nmc=1000 seed=7893 plots=trace nbi=200;
ods select Parameters REparameters PostSumInt tracepanel;
parms b0 0 b1 0 s2 1 s2g 1;
prior b: ~ normal(0, var = 10000);
prior s: ~ igamma(0.01, scale = 0.01);
random gamma ~ normal(0, var = s2g) subject=family monitor=(gamma);
mu = b0 + b1 * gf + gamma;
model height ~ normal(mu, var = s2);
run;
ods graphics off;
run;
quit;
