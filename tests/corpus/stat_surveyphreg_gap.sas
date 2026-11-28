/* expect-rc: 2
   STAT-SURVEYPHREG-001 boundary: features owned by later SURVEYPHREG tickets
   (CLASS, DOMAIN, replication methods and REPWEIGHTS, TIES=EFRON, several
   covariates, counting process input, NOMCAR, RATE=, DF=, CLPARM, a second FREQ statement) must fail visibly
   (D-009 gap) and print no table at all. Data: invented. */
options nosyntaxcheck nodate nonumber nocenter linesize=160;
title;
data s;
input st psu w t c x z g $;
datalines;
1 1 2 5.1 1 1.2 3 a
1 1 2 3.4 0 0.5 1 b
1 2 3 2.2 1 0.3 2 a
1 2 3 9.0 1 1.9 5 b
2 1 4 8.1 1 1.6 2 a
2 1 4 2.9 1 0.2 4 b
2 2 2 3.7 1 2.2 1 a
2 2 2 6.8 1 0.9 3 b
;
proc surveyphreg data=s; strata st; cluster psu; weight w; class g; model t*c(0)=g; run;
proc surveyphreg data=s; strata st; cluster psu; weight w; domain g; model t*c(0)=x; run;
proc surveyphreg data=s varmethod=jk; strata st; cluster psu; weight w; model t*c(0)=x; run;
proc surveyphreg data=s; weight w; repweights z; model t*c(0)=x; run;
proc surveyphreg data=s; strata st; cluster psu; weight w; model t*c(0)=x / ties=efron; run;
proc surveyphreg data=s; strata st; cluster psu; weight w; model t*c(0)=x z; run;
proc surveyphreg data=s; strata st; cluster psu; weight w; model (z, t)*c(0)=x; run;
proc surveyphreg data=s nomcar; strata st; cluster psu; weight w; model t*c(0)=x; run;
proc surveyphreg data=s rate=0.1; strata st; cluster psu; weight w; model t*c(0)=x; run;
proc surveyphreg data=s; strata st; cluster psu; weight w; model t*c(0)=x / df=design; run;
proc surveyphreg data=s; strata st; cluster psu; weight w; freq z; freq z; model t*c(0)=x; run;
proc surveyphreg data=s; strata st; cluster psu; weight w; model t*c(0)=x / clparm; run;
