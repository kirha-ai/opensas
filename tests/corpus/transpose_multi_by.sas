data long;
  length study $2 usubjid $4 param $4;
  input study $ usubjid $ param $ aval;
  datalines;
ST S01 ALT 30
ST S01 AST 25
ST S02 ALT 40
ST S02 AST 35
;
run;
proc transpose data=long out=wide(drop=_name_);
  by study usubjid;
  id param;
  var aval;
run;
proc print data=wide noobs; run;
