/* M9, mixed special missings, FREQ replication and WEIGHT eligibility. */
data sample;
  input x w f;
  datalines;
.A 2 3
. -2 2
.Z . 2
1 1 2
2 0 1
;
ods select MissingValues;
ods output MissingValues=result;
proc univariate data=sample; var x; freq f; run;
data _null_;
  set result;
  file print;
  put 'CODE ' MissValue 1. ' COUNT ' Count 1. ' ALL ' CountNobs 6.2 ' MISSING ' CountNMiss 6.2;
run;

ods select MissingValues;
ods output MissingValues=weighted;
proc univariate data=sample exclnpwgt; var x; freq f; weight w; run;
data _null_;
  set weighted;
  file print;
  put 'CODE ' MissValue 1. ' COUNT ' Count 1. ' ALL ' CountNobs 6.2 ' MISSING ' CountNMiss 6.2;
run;
