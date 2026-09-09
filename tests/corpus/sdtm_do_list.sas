/* Iterate an explicit value list (DO over a list) */
data visits;
  do week = 0, 2, 4, 8, 12;
    day = week * 7;
    output;
  end;
  keep week day;
run;
proc print data=visits; run;
