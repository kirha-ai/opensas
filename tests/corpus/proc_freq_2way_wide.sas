data d;
  input r $ c $;
  datalines;
a p
a q
a r
a s
a t
b p
b u
;
run;
proc freq data=d; tables r*c; run;
