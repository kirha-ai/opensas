/* GH#31b: a DATA-step SET must carry each source column's attached FORMAT
   forward into the output dataset's schema. `set SRC.hadley` reads the real
   32-bit SAS file (workshop->WORKSHOP, gender->$GENDER per pyreadstat); proc
   contents on the SET output `a` must show those formats, not blanks. Without
   the propagation, vvalue()/format resolution over a SET source is blind. */
libname SRC "src/testdata" access=readonly;
data a; set SRC.hadley; run;
proc contents data=a; run;
