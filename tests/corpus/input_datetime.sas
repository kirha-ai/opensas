data d;
  input dt datetime20. iso e8601dt.;
  /* formatted input reads w COLUMNS (Language Reference: Concepts p.515), so the second field starts
     at column 21: the datetime value is 18 wide, padded to the declared 20. */
  datalines;
25DEC2024:10:30:00   2024-12-25T10:30:00
;
run;
proc print data=d noobs; run;
