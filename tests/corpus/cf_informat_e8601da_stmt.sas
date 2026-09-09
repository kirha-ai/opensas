/* GH#52: e8601da. (ISO yyyy-mm-dd) on the DATA-step INPUT-statement path —
   both the INFORMAT-statement form and the :modifier form must read to a SAS
   day, same as input(x, e8601da.). All three want 23134. */
data a; informat d e8601da.; input d; datalines;
2023-05-04
;
run;
data _null_; set a; put "COL=" d; run;

data b; input d : e8601da.; datalines;
2023-05-04
;
run;
data _null_; set b; put "MOD=" d; run;

data c; input d : e8601da10.; datalines;
2023-05-04
;
run;
data _null_; set c; put "WID=" d; run;
