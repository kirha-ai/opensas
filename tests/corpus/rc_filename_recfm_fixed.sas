/* GAP-gapsexitingone §5d — RECFM=F (fixed-length records) is a documented
   FILENAME record form (valid SAS 9.4); opensas's reader is variable-length
   only, so the refusal is a gap → rc 2. A garbage value (recfm=bogus) stays
   rc 1 "Invalid value for the RECFM= FILENAME option." (main.zig §5d test).
   expect-rc: 2 */
data a;
  x = 1;
run;
proc print data=a;
run;
filename f "x.txt" recfm=f;
