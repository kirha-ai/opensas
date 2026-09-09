data t;
  input a $ b $ c $;
  datalines;
a1 b1 c1
a1 b1 c2
a1 b2 c1
a1 b2 c2
a2 b1 c1
a2 b1 c1
a2 b2 c1
a2 b2 c2
;
run;

proc freq data=t;
  tables a*b*c;
run;

proc freq data=t noprint;
  tables a*b*c / out=f(rename=(count=count_));
run;

proc print data=f;
run;
