options ls=256;ods graphics off;ods exclude all;
%macro p(fam,shape,mask);
data d;do n=100;do g=0 to 1000;do i=1 to n;v=(i-.41)/(n+.18);u=.5+.5*sign(2*v-1)*abs(2*v-1)**(1+g*.006);
%if &fam=ln %then %do;x=3+exp(&shape*quantile('normal',u));%end;
%else %do;x=3+(-log1px(-u))**(1/&shape);%end;
output;end;end;end;run;
data gof;length n g Stat pValue 8 TestLab $4 pSign $1;stop;run;
ods output GoodnessOfFit=gof ParameterEstimates=pars;
proc univariate data=d noprint;by n g;histogram x / noplot
%if &fam=ln %then %do;
lognormal(theta=est %if &mask=0 or &mask=1 %then %do; sigma=&shape %end; %if &mask=0 or &mask=2 %then %do; zeta=0 %end;)
%end;
%else %do;
weibull(theta=est %if &mask=0 or &mask=1 %then %do; c=&shape %end; %if &mask=0 or &mask=2 %then %do; sigma=1 %end; maxiter=100)
%end;
;run;
data shapes;set pars;by n g;retain FitShape;
%if &fam=ln %then %do;if Symbol='Sigma' then FitShape=Estimate;%end;
%else %do;if Symbol='C' then FitShape=Estimate;%end;
if last.g then output;keep n g FitShape;run;
ods exclude none;
data _null_;merge gof(in=ok) shapes;by n g;if ok;file print;put "&fam.&mask._&shape|" n best8. '|' g best8. '|' TestLab '|' Stat best32. '|' pValue best32. '|' pSign '|' FitShape best32.;run;
ods exclude all;
%mend;
%macro grid;
%do si=15 %to 295 %by 10;
%let sh=%sysevalf(&si/100);%p(ln,&sh,0);
%end;%mend;%grid;
