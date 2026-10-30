/* A permanent format built from a CNTLIN= control dataset whose FMTNAME has
   underscores (FMT_NAME_WITH_UNDERSCORES), then resolved by name at apply time.
   Guards GAP-permformat (CNTLIN build) x underscore format-name parsing
   together, verified end-to-end. */
data ctl;
  length fmtname $32 label $20;
  fmtname="FMT_NAME_WITH_UNDERSCORES"; start=1; end=1; label="Screening"; output;
  fmtname="FMT_NAME_WITH_UNDERSCORES"; start=2; end=3; label="Treatment"; output;
run;
proc format library=work cntlin=ctl; run;
data sv;
  input visitnum;
  vislbl = put(visitnum, FMT_NAME_WITH_UNDERSCORES.);
  datalines;
1
2
3
;
run;
proc print data=sv noobs; run;
