options nodate nonumber;
data d;input g c x w f id $;datalines;
1 2 10 0 2 A
1 1 20 1 3 B
1 2 30 . 1 C
1 1 . 1 1 D
2 1 40 0 1 E
;
proc univariate data=d(where=(x ne 10)) idout freq modes nextrobs=3 nextrval=3 outtable=wt;
by g;class c(order=internal missing);var x;id id;freq f;weight w;
output out=o n=n nmiss=nm nobs=no mode=m pctlpts=0 50 100 pctlpre=p;
run;
data _null_;set o;file print;put g= c= id= n= nm= no= m= p0= p50= p100=;run;
data _null_;set wt;file print;put _VAR_= _NOBS_= _NMISS_= _SUMWGT_= _MODE_= _MEDIAN_= _NORMAL_=;run;
data empty;set d(obs=0);run;
proc univariate data=empty noprint;var x;output out=e n=n nmiss=nm nobs=no mean=m;run;
proc contents data=e;run;
data rounded;input x y;datalines;
-2.5 0.15
-1.5 0.25
0.5 0.35
2.5 0.45
;
proc univariate data=rounded noprint round=1 .1;var x y;output out=r mean=mx my min=lx ly max=hx hy;run;
data _null_;set r;file print;put mx= my= lx= ly= hx= hy=;run;
