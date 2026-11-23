options nodate nonumber;
data d; x=.; y=.; g=.; h=.; stop; run;

proc corr data=d; var x y; run; proc freq data=d; tables g; run; proc univariate data=d; var x; run;
