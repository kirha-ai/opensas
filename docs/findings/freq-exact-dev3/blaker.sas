options nodate nonumber; ods graphics off;
%put SAS_VERSION=&sysvlong;
data d; input x w; datalines;
1 2
2 8
;
ods output BinomialCLs=limits;
proc freq data=d; weight w; tables x / binomial(cl=blaker) noprint; run;
proc print data=limits; format _numeric_ best32.; run;
data z; input x w; datalines;
1 0
2 10
;
proc freq data=z; weight w / zeros; tables x / binomial(cl=(blaker exact) level=1) noprint; run;
proc freq data=z; weight w / zeros; tables x / binomial(cl=blaker level=2) noprint; run;
data f; input x w; datalines;
1 2.5
2 7.5
;
proc freq data=f; weight w; tables x / binomial(cl=blaker) noprint; run;
