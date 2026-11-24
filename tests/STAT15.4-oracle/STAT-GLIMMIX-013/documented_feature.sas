/* STAT-GLIMMIX-013: GLIMMIX — Pseudo-likelihood Estimation for Weighted Multilevel Models / GLM Mode or GLMM Mode / Exploring and Comparing Covariance Matrices
 * Source: S154 / Chapter 52 / `Pseudo-likelihood Estimation for Weighted Multilevel Models` (PDF pp. 3844–3847); S154 / Chapter 52 / `GLM Mode or GLMM Mode` (PDF pp. 3847–3848); S154 / Chapter 52 / `Exploring and Comparing Covariance Matrices` (PDF pp. 3861–3862).
 * Discriminates: Example 52.9: Testing Equality of Covariance and Correlation Matrices
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

proc print data=Sashelp.iris(obs=10);
run;
data iris_univ;
set sashelp.iris;
retain id 0;
array y (4) SepalLength SepalWidth PetalLength PetalWidth;
id+1;
do var=1 to 4;
response = y{var};
output;
end;
drop SepalLength SepalWidth PetalLength PetalWidth:;
run;
ods select FitStatistics CovParms CovTests;
proc glimmix data=iris_univ;
class species var id;
model response = species*var;
random _residual_ / type=un group=species subject=id;
covtest homogeneity;
run;
ods select FitStatistics CovParms CovTests;
proc glimmix data=iris_univ;
class species var id;
model response = species*var;
random _residual_ / type=unr group=species subject=id;
covtest 'Equal Covariance Matrices' homogeneity;
covtest 'Equal Correlation Matrices' general
0 0 0 0 1 0 0 0 0 0
0 0 0 0 -1 0 0 0 0 0,
0 0 0 0 1 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0
0 0 0 0 -1 0 0 0 0 0,
0 0 0 0 0 1 0 0 0 0
0 0 0 0 0 -1 0 0 0 0,
0 0 0 0 0 1 0 0 0 0
0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 -1 0 0 0 0,
0 0 0 0 0 0 1 0 0 0
0 0 0 0 0 0 -1 0 0 0,
0 0 0 0 0 0 1 0 0 0
0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 -1 0 0 0,
0 0 0 0 0 0 0 1 0 0
0 0 0 0 0 0 0 -1 0 0,
0 0 0 0 0 0 0 1 0 0
0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 -1 0 0,
0 0 0 0 0 0 0 0 1 0
0 0 0 0 0 0 0 0 -1 0,
0 0 0 0 0 0 0 0 1 0
0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 -1 0,
0 0 0 0 0 0 0 0 0 1
0 0 0 0 0 0 0 0 0 -1,
0 0 0 0 0 0 0 0 0 1
0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 -1 / estimates;
run;
