data long;
  length param $4 pname $12;
  input param $ pname $ aval;
  datalines;
ALT Alanine 30
AST Aspartate 25
BILI Bilirubin 1
;
run;
proc transpose data=long out=wide(drop=_name_);
  id param;
  idlabel pname;
  var aval;
run;
proc print data=wide label noobs; run;
proc contents data=wide; run;
