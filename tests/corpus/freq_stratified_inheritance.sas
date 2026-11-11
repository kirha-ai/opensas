options nosyntaxcheck; ods graphics off;
data migraine;
input s r c n;
datalines;
1 1 1 16
1 1 2 11
1 2 1 5
1 2 2 20
2 1 1 12
2 1 2 16
2 2 1 7
2 2 2 19
;
run;
proc freq data=migraine; tables s*r*c / riskdiff(common cl=newcombe column=2 norisks) noprint; weight n;run;
proc freq data=migraine; tables s*r*c / riskdiff(common cl=newcombe norisks) commonriskdiff(cl=mr) noprint; weight n;run;
proc freq data=migraine; tables s*r*c / riskdiff(common column=2 column=both norisks) noprint; weight n;run;
proc freq data=migraine; tables s*r*c / riskdiff(common cl=newcombe norisks) commonriskdiff(test printwts) noprint; weight n;run;
