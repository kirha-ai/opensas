data long;
  length usubjid $4 param $4;
  input usubjid $ param $ aval;
  datalines;
S01 ALT 30
S01 AST 25
S02 ALT 40
S02 AST 35
;
run;
proc transpose data=long out=wide(drop=_name_);
  by usubjid; id param; var aval;
run;
proc transpose data=wide out=back name=param;
  by usubjid; var ALT AST;
run;
proc print data=back noobs; run;
