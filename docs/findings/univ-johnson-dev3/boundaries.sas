options nonumber nodate;
data j; do i=1 to 51; z=probit((i-.375)/51.25); b=1/(1+exp(-z/.7)); u=2*sinh(z/1.1); normal=z; output; end; run;
%macro fit(v,f,opts,label);
title "&label"; proc univariate data=j; var &v; histogram &v / &f(fitmethod=&opts) noplot; run;
%mend;
%fit(b,sb,moments theta=est sigma=est,Symmetric SB moments);
%fit(u,su,moments,Symmetric SU moments);
%fit(normal,su,moments,Normal SU moments);
%fit(normal,su,mle optseed=42 optmaxstarts=1,Normal SU MLE);
%fit(u,su,mle optseed=42 optmaxstarts=1 optboundrange=2 opttolerance=1e-10,SU convergence controls);
%fit(u,su,mle optseed=42 optmaxstarts=1 optmaxiter=1 optprint,SU limited trace);
data edge; input b @@; datalines;
0 .2 .4 .6 .8 1
;
proc univariate data=edge; histogram b / sb(fitmethod=mle) noplot; run;
