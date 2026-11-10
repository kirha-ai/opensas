options nodate nonumber;
data d;
input g x y w f id $;
label x='Example X';
datalines;
1 -2.5 20 0 1 A
1 -1.5 30 1 2 B
1 0.5 40 2 1 C
1 0.5 50 3 1 D
1 2.5 60 . 1 E
1 . 70 1 1 F
;
proc univariate data=d freq modes nextrval=2 nextrobs=2 round=1 outtable=t idout;
var x y; id id;
output out=o n=nx ny nobs=nox noy nmiss=mx my geomean=gx gy harmean=hx hy pctlpts=85.125 20 50 pctlpre=x_ y_ pctlname=high;
run;
proc contents data=o varnum; run;
proc print data=o; run;
proc contents data=t varnum; run;
proc print data=t; run;
proc univariate data=d noprint outtable=tw;
var x; weight w; freq f;
output out=ow n=n nobs=no nmiss=nm q2=q mode=m geomean=g harmean=h pctlpts=0 25 50 75 100 pctlpre=p;
run;
proc print data=ow; run;
proc print data=tw; run;
