data _null_; file print; put 'Case freq_weight_zeros_both'; run;
data sample;input x w1 w2 label $;datalines;
1 0 3 A
3 2 1 B
7 1 2 C
;
run;
proc freq data=sample;tables x;weight w1 / zeros;weight w2 / zeros;run;

data _null_; file print; put 'Case freq_weight_zeros_first'; run;
data sample;input x w1 w2 label $;datalines;
1 0 3 A
3 2 1 B
7 1 2 C
;
run;
proc freq data=sample;tables x;weight w1 / zeros;weight w2;run;

data _null_; file print; put 'Case freq_weight_zeros_second'; run;
data sample;input x w1 w2 label $;datalines;
1 0 3 A
3 2 1 B
7 1 2 C
;
run;
proc freq data=sample;tables x;weight w1;weight w2 / zeros;run;
