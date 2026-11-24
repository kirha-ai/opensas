/* STAT-ADAPTIVEREG-006: ADAPTIVEREG — SCORE
 * Source: S154 / Chapter 28 / `SCORE Statement` (PDF pp. 1073–1074).
 * Discriminates: Example 28.1: Surface Fitting with Many Noisy Variables; explicit statements: SCORE
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data artificial;
drop i;
array X{10};
do i=1 to 400;
do j=1 to 10;
X{j} = ranuni(1);
end;
Y = 40*exp(8*((X1-0.5)**2+(X2-0.5)**2))/
(exp(8*((X1-0.2)**2+(X2-0.7)**2))+
exp(8*((X1-0.7)**2+(X2-0.2)**2)))+rannor(1);
output;
end;
run;
ods graphics on;
proc adaptivereg data=artificial plots=fit;
model y=x1-x10;
run;
data score;
do X1=0 to 1 by 0.01;
do X2=0 to 1 by 0.01;
Y=40*exp(8*((X1-0.5)**2+(X2-0.5)**2))/
(exp(8*((X1-0.2)**2+(X2-0.7)**2))+
exp(8*((X1-0.7)**2+(X2-0.2)**2)));
output;
end;
end;
run;
proc adaptivereg data=artificial;
model y=x1-x10;
score data=score out=scoreout;
run;
%let off0 = offsetmin=0 offsetmax=0;
%let off0 = xaxisopts=(&off0) yaxisopts=(&off0);
%let eopt = location=outside valign=top textattrs=graphlabeltext;
proc template;
define statgraph surfaces;
begingraph / designheight=360px;
layout lattice/columns=2;
layout overlay / &off0;
entry "True Model" / &eopt;
contourplotparm z=y y=x2 x=x1;
endlayout;
layout overlay / &off0;
entry "Fitted Model" / &eopt;
contourplotparm z=pred y=x2 x=x1;
endlayout;
endlayout;
endgraph;
end;
run;
proc sgrender data=scoreout template=surfaces;
run;
data artificial;
drop i;
array x{10};
do i=1 to 400;
do j=1 to 10;
x{j} = ranuni(12345);
end;
y = 40*exp(8*((x1-0.5)**2+(x2-0.5)**2))/
(exp(8*((x1-0.2)**2+(x2-0.7)**2))+
exp(8*((x1-0.7)**2+(x2-0.2)**2)))+rannor(1);
output;
end;
run;
proc adaptivereg data=artificial;
model y=x1-x10;
run;
