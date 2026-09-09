/* GH#34 ISS-fmtcatalog: user format DEFINITIONS loaded from a
   formats.sas7bcat catalog via LIBNAME + OPTIONS FMTSEARCH=, resolved by
   put() and by an attached (sas7bdat) format on PROC PRINT. */
libname LIB "src/testdata";
options fmtsearch=(LIB);

data _null_;
  x = 1; r = put(x, WORKSHOP.);
  x = 2; s = put(x, WORKSHOP.);
  put "WORKSHOP: 1=[" r "] 2=[" s "]";
  gf = put('f', $GENDER.);
  gm = put('m', $GENDER.);
  put "GENDER: f=[" gf "] m=[" gm "]";
run;

/* End-to-end: hadley.sas7bdat carries attached formats WORKSHOP + $GENDER. */
data a; set LIB.hadley; run;
proc print data=a(obs=3); run;
