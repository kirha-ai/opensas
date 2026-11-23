/* Three ordinal categories with nonzero margins; exercise interior. */
options nodate nonumber linesize=120 pagesize=max nostimer nofullstimer;
data sample;
  input r c n;
  datalines;
1 1 2
1 2 1
1 3 1
2 1 0
2 2 2
2 3 1
3 1 1
3 2 0
3 3 3
;
run;

proc corr data=sample polychoric;
  var r c;
  freq n;
run;
