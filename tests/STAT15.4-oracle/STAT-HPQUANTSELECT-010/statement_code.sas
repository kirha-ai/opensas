/* STAT-HPQUANTSELECT-010: HPQUANTSELECT — CODE
 * Source: S154 / Chapter 66 / `CODE Statement` (PDF p. 4988).
 * Discriminates: Generate DATA step scoring code, execute it against the input rows, and print the scored data.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data sample;
call streaminit(314159);
do id=1 to 120;
 x=rand('normal'); z=rand('normal'); w=rand('normal'); group=1+mod(id,3);
 y=2+1.5*x-0.6*z+0.4*group+rand('normal');
 role=mod(id,4); output;
end;
run;
filename _orcode "%sysfunc(pathname(work))/_oracle_score.sas";
proc hpquantselect data=sample;
class group;
model y=x z w group / quantile=0.5 clb;
code file="%sysfunc(pathname(work))/_oracle_score.sas";
performance nthreads=1;
run;
data scored; set sample; %include _orcode; run; proc print data=scored(obs=10); run;
