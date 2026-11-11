/* Independent options.sas includes TABLES=RESTORE and default TEST selections. */
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
title 'K'; proc freq data=migraine; tables s*r*c / commonriskdiff(cl=k test printwts) noprint; weight n; run;
title 'NC'; proc freq data=migraine; tables s*r*c / commonriskdiff(cl=(newcombe newcombemr) test printwts) noprint; weight n; run;
title 'NONE'; proc freq data=migraine; tables s*r*c / commonriskdiff(cl=none test printwts) noprint; weight n; run;
title 'CMH'; proc freq data=migraine; tables s*r*c / cmh cmh1 noprint; weight n; run;
title 'DF'; proc freq data=migraine; tables s*r*c / agree(dfsym=2.5 tables=restore) noprint; weight n; run;
