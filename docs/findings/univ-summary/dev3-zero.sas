options nodate nonumber;
data z;input x w;datalines;
10 0
20 0
30 0
;
proc univariate data=z noprint;var x;weight w;output out=o n=n mean=m median=med mode=mode css=css sum=sum pctlpts=0 25 50 75 100 pctlpre=p;run;proc print;run;
data one;input x;datalines;
7
;
proc univariate data=one noprint;var x;output out=q mode=m n=n;run;proc print;run;
