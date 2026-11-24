/* STAT-GENMOD-007: GENMOD — REPEATED / Generalized Estimating Equations
 * Source: S154 / Chapter 51 / `REPEATED Statement` (PDF pp. 3560–3565); S154 / Chapter 51 / `Generalized Estimating Equations` (PDF pp. 3591–3600).
 * Discriminates: Example 51.5: GEE for Binary Data with Logit Link Function; explicit statements: REPEATED
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

/* Seeded synthetic repeated binary outcomes, not the abbreviated source data. */
data Resp;
call streaminit(314159);
length treatment sex $1;
array v{4} Visit1-Visit4;
do id=1 to 80;
 center=1+mod(id,2); if mod(id,3)=0 then treatment='P'; else treatment='A';
 if mod(id,4)<2 then sex='M'; else sex='F';
 age=25+mod(id*7,40); baseline=rand('bernoulli',0.4); u=0.6*rand('normal');
 do j=1 to 4; v{j}=rand('bernoulli',1/(1+exp(-(-0.5+0.3*(treatment='A')+0.2*baseline+u+0.1*j)))); end;
 output;
end;
drop j u;
run;
data Resp;
set Resp;
Visit=1;
Outcome=Visit1;
output;
Visit=2;
Outcome=Visit2;
output;
Visit=3;
Outcome=Visit3;
output;
Visit=4;
Outcome=Visit4;
output;
run;
proc genmod data=resp;
class id treatment(ref="P") center(ref="1") sex(ref="M")
baseline(ref="0");
model outcome(event='1')=treatment center sex age baseline / dist=bin;
repeated subject=id(center) / corr=unstr corrw;
run;
