data long;
  length usubjid $4 visit $4 result $6;
  input usubjid $ visit $ result $;
  datalines;
S01 V1 Normal
S01 V2 High
S02 V1 Low
S02 V2 Normal
;
run;
proc transpose data=long out=wide(drop=_name_);
  by usubjid;
  id visit;
  var result;
run;
proc print data=wide noobs; run;
