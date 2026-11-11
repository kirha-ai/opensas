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
proc freq data=migraine; tables s*r*c / all cmh1 noprint; weight n; run;
