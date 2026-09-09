/* The exact SV VISNUM chain (QA-svpostfix): a permanent format built from a
   CNTLIN= control dataset whose FMTNAME has underscores (VISNUM_ALL_PERIOD),
   then resolved by name at apply time. Guards GAP-permformat (CNTLIN build) x
   QA-svvisnum f93d388 (name parse not truncating at '_') together — the SV
   codelist path, verified end-to-end. */
data ctl;
  length fmtname $32 label $20;
  fmtname="VISNUM_ALL_PERIOD"; start=1; end=1; label="Screening"; output;
  fmtname="VISNUM_ALL_PERIOD"; start=2; end=3; label="Treatment"; output;
run;
proc format library=work cntlin=ctl; run;
data sv;
  input visitnum;
  vislbl = put(visitnum, VISNUM_ALL_PERIOD.);
  datalines;
1
2
3
;
run;
proc print data=sv noobs; run;
