/* SAS invalid_bounds.sas: DFSYM=0 selects default3 DF; negative values are errors. */
options nosyntaxcheck;
ods graphics off;
data asym;
input r c n;
datalines;
1 1 18
1 2 3
1 3 1
2 1 7
2 2 12
2 3 4
3 1 2
3 2 9
3 3 24
;
title 'dfsym=0';proc freq data=asym;tables r*c / agree(dfsym=0) noprint;weight n;run;
