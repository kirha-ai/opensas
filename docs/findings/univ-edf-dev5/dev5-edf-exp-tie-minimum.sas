options ls=256;ods graphics off;ods exclude all;
data d;do m=3,4,5;do k=1,2,5;do i=1 to k;x=3;output;end;do i=1 to m;u=(i-.5)/m;x=3-4*log1px(-u);output;end;end;end;run;
ods output GoodnessOfFit=gof;
proc univariate data=d noprint;by m k;histogram x / noplot exponential(theta=est sigma=4);run;
ods exclude none;
data _null_;set gof;file print;put m best8. '|' k best8. '|' TestLab;run;
