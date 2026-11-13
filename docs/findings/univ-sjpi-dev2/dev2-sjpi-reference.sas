ods graphics off;
data _null_;file print;put "SAS_VERSION=&sysvlong4";run;
%macro check(id);
ods exclude all;
ods output UnivariateStatistics=stats&id;
proc kde data=d;univar x / plots=none unistats sjpitol=1e-12;run;
ods exclude none;
data _null_;set stats&id;if descr='Bandwidth';file print;put "KDE &id " x=best32.;run;
proc univariate data=d noprint;histogram x / noplot kernel(c=sjpi) outkernel=k&id;run;
data _null_;set k&id(obs=1);file print;put "UNIV &id " _c_=best32.;run;
%mend;
data d;input x @@;datalines;
1 2 3 4 6 8 10 15
;
%check(n8);
data d;input x @@;datalines;
-8 -3 -2 -1 0 1 2 3 8
;
%check(n9);
data d;input x @@;datalines;
0 1 2 3
;
%check(n4);
data d;input x @@;datalines;
0 0 1 1 2 2 3 3
;
%check(ties);
data d;input x @@;datalines;
1 2 3 4 6 8 10 150
;
%check(outlier);
