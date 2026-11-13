data j; do i=1 to 51; q=(i-.375)/51.25; x=2*((1-q)**(-.3)-1)/.3; output; end; run;
proc univariate data=j; histogram x / pareto(fitmethod=foo) noplot; run;
proc univariate data=j; histogram x / beta(fitmethod=foo) noplot; run;
proc univariate data=j; histogram x / power(fitmethod=foo) noplot; run;
