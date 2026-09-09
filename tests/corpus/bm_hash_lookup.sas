data arms; length subjid $4 arm $8; input subjid $ arm $; datalines;
S001 Active
S002 Placebo
S003 Active
;
run;
data enriched;
  length subjid $4 arm $8;
  declare hash h(dataset: "arms");
  rc0=h.defineKey("subjid");
  rc0=h.defineData("arm");
  rc0=h.defineDone();
  subjid="S003"; arm=""; rc=h.find(); output;
  subjid="S001"; arm=""; rc=h.find(); output;
  subjid="S099"; arm=""; rc=h.find(); output;
  keep subjid arm rc;
run;
proc print data=enriched noobs; run;
