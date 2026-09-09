/* ISS-mergereset (GH#44): when the LAST-listed dataset is exhausted within a
   BY group, a var COMMON to both must reset to the live source's value, while a
   var UNIQUE to the exhausted source holds its last value. a has 3 rows per key,
   b has 1: row1 takes b's visitdy=22; rows 2-3 reset to a's visitdy=. (live),
   but visitnum (only in b) stays 2002 for all three. */
data a;
  length id dtc visitdy 8;
  visitdy = .;
  id = 1; dtc = 1; output;
  id = 1; dtc = 1; output;
  id = 1; dtc = 1; output;
run;

data b;
  length id dtc visitnum visitdy 8;
  id = 1; dtc = 1; visitnum = 2002; visitdy = 22; output;
run;

data _null_;
  merge a(in=x) b;
  by id dtc;
  if x;
  put "id=" id " dtc=" dtc " visitdy=" visitdy " visitnum=" visitnum;
run;
