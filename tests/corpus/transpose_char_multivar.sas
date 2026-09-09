data long;
  input usubjid $ param1 $ param2 $;
  datalines;
S01 Normal High
S02 Low Normal
;
run;
/* Single-type (all-char) multi-VAR list must still transpose —
   only a MIXED char/num VAR list errors (BUG-transposemixedvar). */
proc transpose data=long out=wide;
  by usubjid;
  var param1 param2;
run;
proc print data=wide noobs; run;
