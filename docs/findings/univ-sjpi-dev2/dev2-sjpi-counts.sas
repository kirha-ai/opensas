ods graphics off;
data base;input v @@;datalines;
-8 -3 -2 -1 0 1 2 3 8
;
data all;do id=0 to 2;do k=1 to 9;set base point=k;x=v+(id-1)*.01;output;end;end;stop;run;
ods exclude all;ods output UnivariateStatistics=stats;
proc kde data=all;by id;univar x / ngrid=201 gridl=-8.1 gridu=8.1 plots=none unistats sjpitol=1e-12 out=k;run;
ods exclude none;
proc print data=stats;format _numeric_ best32.;run;
data _null_;set k;file print;if count>0 then put _all_;run;
