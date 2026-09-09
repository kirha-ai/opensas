data _null_;
  x = 1;
  if x = 1 then goto skip;
  put "not skipped";
  skip:
  put "at skip";
run;
