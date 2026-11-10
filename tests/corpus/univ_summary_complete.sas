options nodate nonumber;
data d;
input x y w f g;
datalines;
0 100 1 1 1
10 200 1 2 1
20 300 1 1 2
30 400 1 1 1
;
proc univariate data=d noprint pctldef=4;
var x y;
output out=o mean=mx my p25=qx qy nobs=no nmiss=nm;
output out=p pctlpts=85.125 20 50 pctlpre=x_ y_ pctlname=high;
run;
data _null_;set o;file print;put mx= my= qx= qy= no= nm=;run;
data _null_;set p;file print;put x_high= y_high= x_20= y_20= x_50= y_50=;run;
proc univariate data=d noprint;
by g notsorted;freq f;weight w;var x;
output out=b n=n nobs=no q2=q mode=m;
run;
data _null_;set b;file print;put g= n= no= q= m=;run;
proc univariate data=d noprint vardef=n;
var x y;
output out=v skew=sk kurt=ku geomean=gx gy harmean=hx hy;
run;
data _null_;set v;file print;put sk= ku= gx= hy=;run;
