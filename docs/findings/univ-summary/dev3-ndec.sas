data d;x=1;output;x=2;output;run;
proc univariate data=d noprint;var x;output out=o pctlpts=85.123456789 pctlpre=p pctlndec=9;run;
proc contents data=o out=c noprint;run;
data _null_;set c;file print;put name;run;
