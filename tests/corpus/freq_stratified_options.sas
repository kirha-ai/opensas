/* FEAT-freq-stratified: independent SAS evidence /tmp/opensas-stat-batch2/FEAT-freq-stratified/options_defaults.sas; displayed numeric tolerance .00005, I2 percent .005. */
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
title 'test printwts'; proc freq data=migraine; tables s*r*c / commonriskdiff(test printwts) noprint; weight n; run;
title 'cl=score printwts'; proc freq data=migraine; tables s*r*c / commonriskdiff(cl=score printwts) noprint; weight n; run;
title 'cl=mh cl=score printwts'; proc freq data=migraine; tables s*r*c / commonriskdiff(cl=mh cl=score printwts) noprint; weight n; run;
title 'cl=none cl=score test printwts'; proc freq data=migraine; tables s*r*c / commonriskdiff(cl=none cl=score test printwts) noprint; weight n; run;
title 'cl=score cl=none test printwts'; proc freq data=migraine; tables s*r*c / commonriskdiff(cl=score cl=none test printwts) noprint; weight n; run;
title 'cl=(k score) test printwts'; proc freq data=migraine; tables s*r*c / commonriskdiff(cl=(k score) test printwts) noprint; weight n; run;
