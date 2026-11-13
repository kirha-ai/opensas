options nonumber nodate;
data j; do i=1 to 77; z=probit((i-.375)/77.25); b=-2+5/(1+exp((-.7-z)/.8)); u=-4+1.5*sinh((z+.65)/.9); output; end; run;
%macro fit(v,f,opts,label);
title "&label"; proc univariate data=j; var &v; histogram &v / &f(fitmethod=&opts) noplot; run;
%mend;
%fit(u,su,mle delta=.9 gamma=-.65 optseed=321 optmaxstarts=10,Both shapes fixed);
%fit(u,su,mle delta=.9 optseed=321 optmaxstarts=10,Delta fixed);
%fit(u,su,mle gamma=-.65 optseed=321 optmaxstarts=10,Gamma fixed);
