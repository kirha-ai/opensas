options nosyntaxcheck;
ods graphics off;
data diagonal;
input r c n;
datalines;
1 1 9
1 2 0
2 1 0
2 2 6
;
proc freq data=diagonal; tables r*c / agree(details ac1 pabak) trend jt cmh; weight n / zeros; run;
data asym;
input r c n;
datalines;
1 1 6
1 2 16
2 1 2
2 2 4
;
proc freq data=asym; tables r*c / agree(mnullratio=2); weight n; run;
data sparse;
input r c n;
datalines;
1 1 5
1 2 0
1 3 2
2 1 0
2 2 4
2 3 0
3 1 3
3 2 0
3 3 6
;
proc freq data=sparse; tables r*c / agree(dfsym=adjust); weight n / zeros; run;
proc freq data=sparse; tables r*c / agree(dfsym=2.5); weight n / zeros; run;
