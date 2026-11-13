options ls=256;ods graphics off;ods exclude all;
%macro p(fam,mask);
data d;do n=2 to 12;do i=1 to n;u=(i-.5)/n;%if &fam=ln %then %do;x=3+exp(.5*quantile('normal',u));%end;%else %do;x=3+(-log1px(-u))**(1/3);%end;output;end;end;run;
data gof;length n Stat pValue 8 TestLab $4 pSign $1;stop;run;
ods output GoodnessOfFit=gof;
proc univariate data=d noprint;by n;histogram x / noplot
%if &fam=ln %then %do;lognormal(theta=est %if &mask=0 or &mask=1 %then %do; sigma=.5 %end; %if &mask=0 or &mask=2 %then %do; zeta=0 %end;)%end;
%else %do;weibull(theta=est %if &mask=0 or &mask=1 %then %do; c=3 %end; %if &mask=0 or &mask=2 %then %do; sigma=1 %end; maxiter=100)%end;
;run;
ods exclude none;
data _null_;set gof;file print;put "&fam.&mask|" n best8. '|' TestLab;run;
ods exclude all;
%mend;
%macro grid;%do mask=0 %to 3;%p(ln,&mask);%p(wb,&mask);%end;%mend;%grid;
