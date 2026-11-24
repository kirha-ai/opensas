/* STAT-GLM-010: GLM — REPEATED / Repeated Measures Analysis of Variance
 * Source: S154 / Chapter 53 / `REPEATED Statement` (PDF pp. 4100–4104); S154 / Chapter 53 / `Repeated Measures Analysis of Variance` (PDF pp. 4149–4157).
 * Discriminates: Example 53.7: Repeated Measures Analysis of Variance; explicit statements: REPEATED
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data dogs;
input Drug :$12. Depleted $ Histamine0 Histamine1
Histamine3 Histamine5;
LogHistamine0=log(Histamine0);
LogHistamine1=log(Histamine1);
LogHistamine3=log(Histamine3);
LogHistamine5=log(Histamine5);
datalines;
Morphine N .04 .20 .10 .08
Morphine N .02 .06 .02 .02
Morphine N .07 1.40 .48 .24
Morphine N .17 .57 .35 .24
Morphine Y .10 .09 .13 .14
Morphine Y .12 .11 .10 .
Morphine Y .07 .07 .06 .07
Morphine Y .05 .07 .06 .07
Trimethaphan N .03 .62 .31 .22
Trimethaphan N .03 1.05 .73 .60
Trimethaphan N .07 .83 1.07 .80
Trimethaphan N .09 3.13 2.06 1.23
Trimethaphan Y .10 .09 .09 .08
Trimethaphan Y .08 .09 .09 .10
Trimethaphan Y .13 .10 .12 .12
Trimethaphan Y .06 .05 .05 .05
;
proc glm;
class Drug Depleted;
model LogHistamine0--LogHistamine5 =
Drug Depleted Drug*Depleted / nouni;
repeated Time 4 (0 1 3 5) polynomial / summary printe;
run;
