/* STAT-HPFMM-014: HPFMM — Official examples and feature integration regression
 * Source: S154 / Chapter 58 / `Examples: HPFMM Procedure` (PDF pp. 4596–4618).
 * Discriminates: Example 58.3: Enforcing Homogeneity Constraints: Count and Dispersion—It Is All Over!
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data assay;
label dose = 'Dose of quinoline (microg/plate)'
num = 'Observed number of colonies';
input dose @;
logd = log(dose+10);
do i=1 to 3;
input num@;
output;
end;
datalines;
0 15 21 29
10 16 18 21
33 16 26 33
100 27 41 60
333 33 38 41
1000 20 27 42
;
proc hpfmm data=assay seed=314159;
model num = dose logd / dist=Poisson;
run;
proc hpfmm data=assay seed=314159;
model num = dose logd / dist=Poisson k=2
equate=effects(dose logd);
run;
proc hpfmm data=assay seed=314159;
model num = dose logd / dist=Poisson k=2;
restrict 'common dose' dose 1, dose -1;
restrict 'common logd' logd 1, logd -1;
run;
proc hpfmm data=assay(where=(num ne 60)) seed=314159;
model num = dose logd / dist=Poisson k=2
equate=effects(dose logd);
run;
proc hpfmm data=assay(where=(num ne 60)) seed=314159;
model num = dose logd / dist=Poisson;
run;
