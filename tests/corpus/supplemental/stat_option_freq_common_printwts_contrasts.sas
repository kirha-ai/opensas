data _null_; file print; put 'Case freq_common_printwts_mh'; run;
data trial;input s r c w;datalines;
1 1 1 16
1 1 2 11
1 2 1 5
1 2 2 20
2 1 1 7
2 1 2 19
2 2 1 12
2 2 2 16
;
run;
proc freq data=trial;weight w;tables s*r*c / commonriskdiff(cl=klingenberg printwts=mh) noprint;run;

data _null_; file print; put 'Case freq_common_printwts_minrisk'; run;
data trial;input s r c w;datalines;
1 1 1 16
1 1 2 11
1 2 1 5
1 2 2 20
2 1 1 7
2 1 2 19
2 2 1 12
2 2 2 16
;
run;
proc freq data=trial;weight w;tables s*r*c / commonriskdiff(cl=klingenberg printwts=minrisk) noprint;run;

data _null_; file print; put 'Case freq_common_printwts_mr'; run;
data trial;input s r c w;datalines;
1 1 1 16
1 1 2 11
1 2 1 5
1 2 2 20
2 1 1 7
2 1 2 19
2 2 1 12
2 2 2 16
;
run;
proc freq data=trial;weight w;tables s*r*c / commonriskdiff(cl=klingenberg printwts=mr) noprint;run;

data _null_; file print; put 'Case freq_common_printwts_score'; run;
data trial;input s r c w;datalines;
1 1 1 16
1 1 2 11
1 2 1 5
1 2 2 20
2 1 1 7
2 1 2 19
2 2 1 12
2 2 2 16
;
run;
proc freq data=trial;weight w;tables s*r*c / commonriskdiff(cl=klingenberg printwts=score) noprint;run;
