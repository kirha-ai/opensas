/* GH#31 ISS-sas7bdatfmt-real: the sas7bdat READER must attach per-column FORMAT
   names off a REAL, externally-authored SAS file (tidyverse/haven test data,
   32-bit). pyreadstat oracle: workshop->WORKSHOP, gender->$GENDER, rest none.
   Non-circular: the file is not written by opensas, so it cannot share a wrong
   offset assumption with the reader. */
libname SRC "src/testdata" access=readonly;
proc contents data=SRC.hadley; run;
