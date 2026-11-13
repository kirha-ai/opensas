data d; input b x y; datalines;
1 1 3
1 2 5
1 4 4
2 3 1
2 5 2
2 7 9
;
ods output PearsonCorr=pc SimpleStats=ss;
proc corr data=d; by b; var x y; run;
ods output OneWayFreqs=ow CrossTabFreqs=ct;
proc freq data=d; by b; tables x x*y; run;
ods output Moments=mo Quantiles=qu BasicMeasures=bm;
proc univariate data=d; by b; var x y; run;
%macro dump(ds);
proc contents data=&ds varnum; run;
data _null_; set &ds; file print; format _numeric_ best32.; put _all_; run;
%mend;
%dump(pc);%dump(ss);%dump(ow);%dump(ct);%dump(mo);%dump(qu);%dump(bm);
