options nodate nonumber nosyntaxcheck; data d; x=1; y=2; run;
proc freq data=d; tables x / (chisq); run;
proc freq data=d; tables x / missing=0; run;
proc freq data=d; tables x*y / list crosslist; run;
proc freq data=d; tables x*y / sparse nosparse; run;
proc freq data=d; tables x / maxlevels=0; run;
proc freq data=d; tables x*y / format=30.; run;
proc freq data=d compress page; tables x; run;
