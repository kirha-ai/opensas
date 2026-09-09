/* BUG-weightvarcheck regression: a VALID WEIGHT var must keep producing the
   correct weighted stats (only a NONEXISTENT weight var errors now), and a
   VALID UNIVARIATE VAR list must still render. x={10,20,30}, w={3,1,1}:
   weighted Mean=(10*3+20+30)/5=16, Sum=Σwx=80 (unweighted Mean would be 20). */
data d; input x w; datalines;
10 3
20 1
30 1
;
run;
proc means data=d mean sum n; var x; weight w; run;
proc univariate data=d noprint;
  var x;
  weight w;
  output out=s mean=mean sum=sum;
run;
proc print data=s; run;
