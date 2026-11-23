data _null_; file print; put 'Case freq_list_descending'; run;
data sample;input x01 extra x03 x02 s $ y;datalines;
1 9 3 2 A 5
3 11 5 4 B 7
;
run;
proc freq data=sample;tables x03-x01;run;

data _null_; file print; put 'Case freq_list_nosparse'; run;
data sample;input g r c w;datalines;
1 1 1 4
1 1 2 1
1 2 1 2
1 2 2 3
2 1 1 3
2 2 2 7
2 3 3 0
;
run;
proc freq data=sample ;where g=2;weight w / zeros;tables r*c / list nosparse;run;

data _null_; file print; put 'Case freq_list_numbered'; run;
data sample;input x01 extra x03 x02 s $ y;datalines;
1 9 3 2 A 5
3 11 5 4 B 7
;
run;
proc freq data=sample;tables x01-x03;run;

data _null_; file print; put 'Case freq_list_sparse'; run;
data sample;input g r c w;datalines;
1 1 1 4
1 1 2 1
1 2 1 2
1 2 2 3
2 1 1 3
2 2 2 7
2 3 3 0
;
run;
proc freq data=sample ;where g=2;weight w / zeros;tables r*c / list sparse;run;
