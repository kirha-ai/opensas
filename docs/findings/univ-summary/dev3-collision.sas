data d;x=0;output;x=100;output;run;
proc univariate data=d noprint pctldef=1;var x;output out=o pctlpts=50.001 50.009 pctlpre=p mean=a sum=a;run;
proc print data=o;run;
proc contents data=o out=c noprint;run;data _null_;set c;file print;put name label;run;
