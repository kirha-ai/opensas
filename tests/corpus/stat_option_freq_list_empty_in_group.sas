data sample;input x01 extra x03 x02 s $ y;datalines;
1 9 3 2 A 5
3 11 5 4 B 7
;
run;
proc freq data=sample;tables (nothing: x01)*y / out=cells;run;data _null_;file print;set cells;put 'CELL ' x01 '|' y '|' count;run;
