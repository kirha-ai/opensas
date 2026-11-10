options nodate nonumber;
data d; input x y; datalines;
0 1
10 2
20 3
30 4
;
proc univariate data=d noprint;
var x y;
output out=o pctlpts=85.125 20 50 33.333 pctlpre=x_ y_ pctlname=high n=n nmiss=nm nobs=no sumwgt=sw mean=m std=s var=v skew=sk kurt=ku sum=su min=mi max=ma range=r uss=u css=c cv=cv stderr=se t=t probt=pt msign=ms probm=pm signrank=sr probs=ps mode=mo p1=p1 p5=p5 p10=p10 q1=q1 median=md q3=q3 p90=p90 p95=p95 p99=p99 qrange=qr gini=gi mad=mad sn=sn qn=qn std_qrange=sqr std_gini=sg std_mad=sm std_sn=ss std_qn=sq geomean=gm harmean=hm;
run;
proc contents data=o varnum out=c noprint; run;
data _null_; set c; file print; put varnum name label; run;
proc print data=o;run;
