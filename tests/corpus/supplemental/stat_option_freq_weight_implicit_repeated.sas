data sample;input x w1 w2 label $;datalines;
1 0 3 A
3 2 1 B
7 1 2 C
;
run;
proc freq data=sample;weight w1;weight w2;run;
