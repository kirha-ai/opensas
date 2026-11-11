/* SAS details_alias.sas verifies simple/weighted detail selection independently. */
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
title 'details'; proc freq data=asym;tables r*c / agree(details) noprint; weight n;run;
title 'kappadetails'; proc freq data=asym;tables r*c / agree(kappadetails) noprint; weight n;run;
title 'wtkappadetails'; proc freq data=asym;tables r*c / agree(wtkappadetails) noprint; weight n;run;
title 'details wtkappadetails'; proc freq data=asym;tables r*c / agree(details wtkappadetails) noprint; weight n;run;
