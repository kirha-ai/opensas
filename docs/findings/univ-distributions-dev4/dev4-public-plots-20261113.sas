ods graphics off;goptions nodisplay;
data d;input b c x f;datalines;
1 1 1 2
1 1 2 1
1 1 . 4
1 2 4 1
1 2 8 1
2 1 3 1
2 1 5 2
2 2 10 1
2 2 14 1
;
proc univariate data=d noprint;by b;class c;freq f;var x;
cdfplot x / normal(mu=0 sigma=2);
ppplot x / normal(mu=0 sigma=2);
qqplot x / normal(mu=est sigma=est);
probplot x / weibull2(theta=0 sigma=2 c=3) rankadj=-.5 nadj=0;
run;
/* Manual pp.307,365,450,457: independent numerical coordinate formulas. */
data _null_;array obs[3] _temporary_ (1 1 2);file print;
do i=1 to 3;
x=obs[i];emp=ifn(i<3,2/3,1);pp=i/3;fitted=cdf('normal',x,0,2);
qprob=(i-.375)/3.25;q=quantile('normal',qprob);
wprob=(i-.5)/3;wq=log(-log1px(-wprob));wy=log(x);
put i= x= emp=best20.12 pp=best20.12 fitted=best20.12 qprob=best20.12 q=best20.12 wprob=best20.12 wq=best20.12 wy=best20.12;
end;run;
