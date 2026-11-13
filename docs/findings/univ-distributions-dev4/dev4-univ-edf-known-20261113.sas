ods graphics off;
ods exclude all;
data d;do n=20,100,500;do g=0 to 40;do i=1 to n;x=quantile('normal',((i-.5)/n)**(1+g*.025));output;end;end;end;run;
ods output GoodnessOfFit=gof;
proc univariate data=d noprint;by n g;histogram x / noplot normal(mu=0 sigma=1);run;
ods exclude none;
data _null_;set gof;file print;put n best8. '|' g best8. '|' TestLab '|' Stat best32. '|' pValue best32. '|' pSign;run;
