%macro probe(n1,n2,a);
data t; input r c n; datalines;
1 1 0
1 2 &n1
2 1 &n2
2 2 0
;
%mend;
%macro probe_case(n1,n2,a,m);
data t; r=1;c=1;n=0;output;r=1;c=2;n=&n1;output;r=2;c=1;n=&n2;output;r=2;c=2;n=0;output;run;
ods output RelRisk1ExactCL=out;
proc freq data=t; weight n / zeros; tables r*c / relrisk alpha=&a; exact relrisk(method=&m); run;
proc print data=out; format _numeric_ best32.;run;
%mend;
%probe_case(2,3,.95,score)
%probe_case(2,3,.95,noscore)
%probe_case(2,5,.94,score)
%probe_case(2,5,.94,noscore)
%probe_case(2,5,.99,score2)
%probe_case(3,5,.99,score2)
%probe_case(4,3,.99,score2)
%probe_case(2,3,.05,score)
%probe_case(2,3,.05,score2)
%probe_case(2,3,.8,score)
