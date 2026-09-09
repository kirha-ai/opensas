data _null_;
  a = 3; b = 5;
  if a lt b then put "lt ok";
  if b gt a then put "gt ok";
  if a ne b then put "ne ok";
  if a le 3 then put "le ok";
  if b ge 5 then put "ge ok";
  if a eq 3 then put "eq ok";
run;
