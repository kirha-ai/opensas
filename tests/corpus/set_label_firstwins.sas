/* BUG-setlabellastwins: across SET/MERGE members a variable's LABEL is
   FIRST-source-wins — the same rule opensas already applies to LENGTH (with
   the multiple-lengths warning), FORMAT, and INFORMAT. opensas took the LAST.
   A var labelled only in a later member still gets that label. */
data a;
  label x = 'From A';
  x = 1;
run;
data b;
  label x = 'From B' y = 'Only B';
  x = 2;
  y = 3;
run;
data both;
  set a b;
run;
proc contents data=both; run;
