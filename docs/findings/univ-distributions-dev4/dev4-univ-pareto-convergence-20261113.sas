ods graphics off;
data d;do g=0 to 10;do i=1 to 8;x=scan('1 2 3 4 6 8 10 15',i)+g;output;end;end;run;
proc univariate data=d noprint;by g;histogram x / noplot pareto(edfnsamples=1 edfseed=17);run;
