data _null_;
  /* BUG-bzstmtcolumn: BZ in column mode must read field blanks as zeros.
     Same 4 columns read two ways: bz4. keeps blanks-as-zeros, plain 4. trims. */
  input @1 bzcol bz4. @1 plaincol 4.;
  put "bzcol=" bzcol " plaincol=" plaincol;
  datalines;
12  0
    0
;
run;
