/* expect-rc: 1; independent SAS completion_edges.sas: CA error, later FC still runs. */
options nosyntaxcheck; ods graphics off;
data descending;
input r c n;
datalines;
3 3 18
3 2 3
3 1 1
2 3 7
2 2 12
2 1 4
1 3 2
1 2 9
1 1 24
;
title 'DESCENDING CA';
proc freq data=descending order=data; tables r*c / agree(printkwts details wtkappadetails) noprint;weight n;run;
title 'DESCENDING FC';
proc freq data=descending order=data; tables r*c / agree(wt=fc printkwts) noprint;weight n;run;
