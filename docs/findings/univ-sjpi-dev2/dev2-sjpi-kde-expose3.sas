ods graphics off;
data d;input x @@;datalines;
-8 -3 -2 -1 0 1 2 3 8
;
%macro probe(id,opts);
ods exclude all;ods output UnivariateStatistics=s_&id;
proc kde data=d;univar x / ngrid=201 unistats plots=none out=k_&id &opts;run;
ods exclude none;
data _null_;set s_&id;if descr='Bandwidth';file print;put "BW &id " x=best32.;run;
data _null_;set k_&id;file print;if count>0 then put "BIN &id " _n_= value=hex16. count=;run;
%mend;
%probe(default,);
%probe(tiny,%str(bwm=0.00000000000000000001));
%probe(truncate,truncate);
