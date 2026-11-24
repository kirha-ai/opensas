/* STAT-GENMOD-006: GENMOD — Zero-Inflated Models / Tweedie Distribution for Generalized Linear Models
 * Source: S154 / Chapter 51 / `Zero-Inflated Models` (PDF pp. 3588–3589); S154 / Chapter 51 / `Tweedie Distribution for Generalized Linear Models` (PDF pp. 3589–3591).
 * Discriminates: Example 51.12: Tweedie Regression
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

%let nObs = 250;
%let nClass = 5;
%let nLevs = 4;
%let seed = 100;
data tmp1;
array c{&nClass};
keep c1-c&nClass yTweedie d1 d2;
/* Tweedie parms */
phi=0.5;
p=1.5;
do i=1 to &nObs;
do j=1 to &nClass;
c{j} = int(ranuni(1)*&nLevs);
end;
d1 = ranuni(&seed);
d2 = ranuni(&seed);
xBeta = 0.5 *((c2<2) - 2*(c1=1) + 0.5*c&nClass + 0.05*d1);
mu = exp(xBeta);
/* Poisson distributions parms */
lambda = mu**(2-p)/(phi*(2-p));
/* Gamma distribution parms */
alpha = (2-p)/(p-1);
gamma = phi*(p-1)*(mu**(p-1));
rpoi = ranpoi(&seed,lambda);
if rpoi=0 then yTweedie=0;
else do;
yTweedie=0;
do j=1 to rpoi;
yTweedie = yTweedie + rangam(&seed,alpha);
end;
yTweedie = yTweedie * gamma;
end;
output;
end;
run;
proc genmod data=tmp1;
class C1-C5;
model yTweedie = C1-C5 D1 D2 / dist=Tweedie type3;
run;
proc genmod data=tmp1;
class C1 C2;
model yTweedie = C1 C2 D1 / dist=Tweedie(p=1.5) type3;
run;
