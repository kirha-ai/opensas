/* STAT-GLMSELECT-019: GLMSELECT — Official examples and feature integration regression
 * Source: S154 / Chapter 56 / `Examples: GLMSELECT Procedure` (PDF pp. 4398–4472).
 * Discriminates: Example 56.6: Elastic Net and External Cross Validation
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
proc glmselect data=sashelp.Leutrain valdata=sashelp.Leutest
plots=coefficients seed=314159;
model y = x1-x7129/
selection=LASSO(steps=120 choose=validate);
run;
proc glmselect data=sashelp.Leutrain valdata=sashelp.Leutest
plots=coefficients seed=314159;
model y = x1-x7129/
selection=elasticnet(steps=120 L2=0.001 choose=validate);
run;
proc glmselect data=sashelp.Leutrain valdata=sashelp.Leutest
plots=coefficients seed=314159;
model y = x1-x7129/
selection=elasticnet(steps=120 choose=validate);
run;
proc glmselect data=sashelp.Leutrain testdata=sashelp.Leutest
plots=coefficients seed=314159;
model y = x1-x7129/
selection=elasticnet(steps=120 choose=cv)cvmethod=split(4);
run;
proc glmselect data=sashelp.Leutrain testdata=sashelp.Leutest
plots=coefficients seed=314159;
model y = x1-x7129/
selection=elasticnet(steps=120 choose=cvex)cvmethod=split(4);
run;
