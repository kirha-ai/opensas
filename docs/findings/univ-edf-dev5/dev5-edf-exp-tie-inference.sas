options ls=256;ods graphics off;ods exclude all;
data d;do m=10,30;do k=1,2,5;do g=0 to 60;do i=1 to k;x=3;output;end;do i=1 to m;u=((i-.5)/m)**(1+g*.04);x=3-4*log1px(-u);output;end;end;end;end;run;
ods output GoodnessOfFit=gof;
proc univariate data=d noprint;by m k g;histogram x / noplot exponential(theta=est sigma=4);run;
ods exclude none;
data _null_;set gof;file print;put m best8. '|' k best8. '|' g best8. '|' TestLab '|' Stat best32. '|' pValue best32. '|' pSign;run;
