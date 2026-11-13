ods graphics off;
data d;input x @@;datalines;
0 1 2 3
;
%macro p(ng);
ods exclude all;ods output UnivariateStatistics=s;
proc kde data=d;univar x / ngrid=&ng plots=none unistats sjpitol=1e-12;run;
ods exclude none;
data _null_;set s;if descr='Bandwidth';file print;put "NGRID=&ng " x=best32.;run;
%mend;
%p(101);%p(129);%p(401);%p(1001);
