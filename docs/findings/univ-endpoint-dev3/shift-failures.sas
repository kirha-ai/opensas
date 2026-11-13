options nonumber nodate;
data d; do shift=0 to 4; do i=1 to 8; x=input(scan("1 2 3 4 6 8 10 15",i),best.)+shift; output; end; end; run;
proc univariate data=d noprint; by shift; histogram x / pareto(edfnsamples=1) noplot; run;
data b; do i=1 to 41; q=(i-.375)/41.25; x=q**2; output; end; run;
title "power alternate sigma=est"; proc univariate data=b; histogram x / power(sigma=est) noplot; run;
title "power alternate theta=est sigma=est"; proc univariate data=b; histogram x / power(theta=est sigma=est) noplot; run;
title "power alternate theta=est sigma=1 alpha=.5"; proc univariate data=b; histogram x / power(theta=est sigma=1 alpha=.5) noplot; run;
