/* Independent SAS alpha=.8:20% labels, frequency5.4, MH CI(.2013,.3462). */
options nosyntaxcheck; ods graphics off;
data fractional;
input s r c n;
datalines;
1 1 1 1.6
1 1 2 1.1
1 2 1 0.5
1 2 2 2
2 1 1 1.2
2 1 2 1.6
2 2 1 0.7
2 2 2 1.9
;
title 'FRACTIONAL COMMON HIGH ALPHA';
proc freq data=fractional;tables s*r*c / commonriskdiff(cl=(mh k mr score newcombe newcombemr) test printwts) cmh(i2) alpha=.8 noprint;weight n;run;
