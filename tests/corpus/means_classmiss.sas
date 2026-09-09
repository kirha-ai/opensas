/* BUG-meansclassmiss: an obs with a MISSING CLASS value is excluded from every
   MEANS analysis (grand total, each _TYPE_, the listing) by DEFAULT; the MISSING
   option (proc-level or `class g / missing`) re-includes it. */
data d; input g x; datalines;
1 10
1 20
. 999
2 30
;
run;
/* default: g=. obs dropped — _TYPE_=0 is FREQ 3 / mean 20, no g=. row */
proc means data=d noprint; class g; var x; output out=o mean=m sum=s n=cnt; run;
proc print data=o noobs; run;
/* `/ missing` re-includes the g=. obs — _TYPE_=0 FREQ 4, and a g=. _TYPE_=1 row */
proc means data=d noprint; class g / missing; var x; output out=o2 mean=m sum=s n=cnt; run;
proc print data=o2 noobs; run;
/* printed listing: default excludes the missing level */
proc means data=d n mean sum; class g; var x; run;
/* proc-level MISSING option re-includes it in the listing */
proc means data=d missing n mean sum; class g; var x; run;
