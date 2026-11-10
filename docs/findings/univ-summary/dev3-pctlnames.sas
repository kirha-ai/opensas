data d;x=1;output;x=2;output;run;
proc univariate data=d noprint;var x;output out=o pctlpts=85.1299 85.125 33.339 66.679 0.0099 pctlpre=p;run;
proc contents data=o out=c noprint;run;data _null_;set c;file print;put name;run;
