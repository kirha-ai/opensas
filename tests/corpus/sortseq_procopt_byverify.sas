/* GAP-sortseq-procopt-verify: PROC SORT's PROC-level SORTSEQ=LINGUISTIC must
   travel with the sorted dataset. The system option is reset to ASCII, so a BY
   verifier that consults only global state rejects the valid linguistic order
   (`apple`, `Banana`, `Zebra`) as byte-unsorted and errhalt skips the final PUT. */

options sortseq=ascii;

data names;
  length name $8;
  input name $ x;
  datalines;
Banana 2
Zebra 3
apple 1
;
run;

proc sort data=names out=sorted sortseq=linguistic;
  by name;
run;

proc print data=sorted noobs;
  by name;
  var x;
run;

data _null_;
  put "later-step-ran";
run;
