/* Independent SAS: row-missing no warning, column-missing one warning and no weighted details. */
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
data rowmissing;set descending;r=4-r;c=4-c;if r=1 then r=.;run;
title 'MISSING ROW WEIGHTED';
proc freq data=rowmissing;tables r*c / missing agree(wtkappadetails) noprint;weight n;run;
title 'MISSING COLUMN WEIGHTED';
proc freq data=rowmissing;tables c*r / missing agree(wtkappadetails) noprint;weight n;run;
