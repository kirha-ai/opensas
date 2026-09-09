/* BUG-sortseq + BUG-procoptswallow: SORTSEQ=LINGUISTIC sorts case-folded
   dictionary order (apple before Banana, where ASCII puts Banana first);
   CONTENTS VARNUM lists variables in creation order, SHORT a compact name
   list. Unknown SORT/CONTENTS header options fail loud (D-002). */
data d;
  input name $;
  datalines;
Banana
apple
cherry
;
run;
proc sort data=d out=o sortseq=linguistic;
  by name;
run;
data _null_; set o; put name; run;
data v;
  input Zebra Apple Mango;
  datalines;
1 2 3
;
run;
proc contents data=v varnum; run;
proc contents data=v short; run;
