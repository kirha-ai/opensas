/* BUG-optmissing: OPTIONS MISSING= sets the display char for a PLAIN missing
   numeric (was parsed-then-dropped → always "."). Special missings (.A/._)
   keep their own letter; `missing='.'` resets to the default. */
options missing='X';
data a;
  input id v w;
  datalines;
1 . .A
2 5 3
;
run;
proc print data=a; run;

data _null_;
  x = .;
  y = ._;
  put x;  /* X — list-PUT honors MISSING= too */
  put y;  /* _ — special missing unaffected */
run;

options missing='.';  /* reset to the default */
proc print data=a; run;
