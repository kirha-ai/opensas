data dm;
  length usubjid $6 country $10;
  input usubjid $ country $;
  datalines;
US-001 UnitedStates
US-002 UnitedStates
CA-001 Canada
UK-001 UnitedKingd
;
run;
proc sql;
  create table us as select usubjid from dm where usubjid like 'US-%';
  create table united as select usubjid from dm where country like 'United%';
quit;
proc print data=us noobs; run;
proc print data=united noobs; run;
