data dm; length subjid $4; input subjid $ age; datalines;
S001 30
S002 45
S003 60
;
run;
data lb; length subjid $4; input subjid $ val; datalines;
S001 5.1
S001 5.5
S003 7.2
S004 9.9
;
run;
data _null_;
  merge dm(in=ind) lb(in=inl);
  by subjid;
  length flag $8;
  if ind and inl then flag="both";
  else if ind then flag="dm_only";
  else flag="lb_only";
  put subjid "age=" age "val=" val flag;
run;
