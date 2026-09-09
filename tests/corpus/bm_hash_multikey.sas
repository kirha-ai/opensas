data ref; length subjid $4 visit $4 result $6; input subjid $ visit $ result $; datalines;
S001 V1 Normal
S001 V2 High
S002 V1 Low
;
run;
data out;
  length subjid $4 visit $4 result $6;
  declare hash h(dataset: "ref");
  rc0=h.defineKey("subjid","visit");
  rc0=h.defineData("result");
  rc0=h.defineDone();
  subjid="S001"; visit="V2"; result=""; rc=h.find(); output;
  subjid="S002"; visit="V1"; result=""; rc=h.find(); output;
  subjid="S001"; visit="V9"; result=""; rc=h.find(); output;
  keep subjid visit result rc;
run;
proc print data=out noobs; run;
