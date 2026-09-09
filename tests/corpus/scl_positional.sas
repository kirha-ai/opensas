/* QA regression: SCL positional fns NOTE/POINT/REWIND/DROPNOTE/DSNAME (dev2
   10e89b2). Round-trip: note a row, rewind, point back, fetch reads the same row. */
data nums; input x; datalines;
10
20
30
40
;
run;
data _null_;
  d   = open("nums");
  rc3 = fetchobs(d, 3);
  n   = note(d);
  rw  = rewind(d);
  rcf = fetch(d);
  v1  = getvarn(d, 1);
  pt  = point(d, n);
  rcp = fetch(d);
  vp  = getvarn(d, 1);
  co  = curobs(d);
  dn  = dropnote(d, n);
  nm  = dsname(d);
  rcc = close(d);
  put "note=" n;
  put "rewind_then_fetch=" v1;
  put "point_then_fetch=" vp " curobs=" co;
  put "dropnote=" dn;
  put "dsname=" nm;
  put "close=" rcc;
run;
