options nosyntaxcheck; ods graphics off;
data mixed;input s r c n;datalines;
1 1 1 16
1 1 2 11
1 2 1 5
1 2 2 20
2 1 1 7
2 1 2 19
2 2 1 12
2 2 2 16
;
proc freq data=mixed; tables s*r*c / cmh(gs(column=2) bdt qor i2) noprint;weight n;run;
proc freq data=mixed; tables s*r*c / gs(column=1) noprint;weight n;run;
