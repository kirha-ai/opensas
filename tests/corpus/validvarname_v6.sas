/* BUG-validvarnamev6: VALIDVARNAME=V6 is not inert. Real SAS refuses to
   create variable names over 8 bytes.
   expect-rc: 1 */
options validvarname=v6;
data longnames;
  length thisisaverylongvariablename 8;
  thisisaverylongvariablename = 42;
run;
