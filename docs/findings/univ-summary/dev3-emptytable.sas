data d;x=.;w=.;output;run;
data empty;set d(obs=0);run;
proc univariate data=empty noprint outtable=t;var x;run;
data _null_;length label $256;ds=open('t');rows=attrn(ds,'nobs');cols=attrn(ds,'nvars');label=attrc(ds,'label');file print;put rows= cols= label=;rc=close(ds);run;
proc univariate data=d noprint outtable=tw;var x;weight w;run;
data _null_;length label $256;ds=open('tw');rows=attrn(ds,'nobs');cols=attrn(ds,'nvars');label=attrc(ds,'label');file print;put rows= cols= label=;rc=close(ds);run;
