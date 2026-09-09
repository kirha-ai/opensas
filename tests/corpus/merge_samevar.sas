/* Locks the SAS same-name-variable rule: when a variable is in BOTH merged
   datasets, the RIGHTMOST dataset's value wins for a matched obs; an unmatched
   key keeps its own side's value. Silent data-corruption class if wrong. */
data a; input id x; datalines;
1 10
2 20
3 30
;
run;
data b; input id x; datalines;
2 200
3 300
4 400
;
run;
data _null_;
  merge a b;
  by id;
  put "id=" id " x=" x;
run;
