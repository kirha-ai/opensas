/* ISS-attriblabeltype (GH#11): a label-only ATTRIB must not type the variable.
 * Per Language Reference: Concepts p.51 only LENGTH=/FORMAT=/INFORMAT= create-or-type a var; LABEL=
 * cannot. So `retain RFICDTC ''` (a char constant, Language Reference: Concepts p.509-510) establishes
 * CHARACTER and the assignment stays char — no char->num conversion to missing. */
data O;
  attrib RFICDTC label="ICF Date";
  retain RFICDTC '';
  RFICDTC="abc";
run;
data _null_;
  set O;
  put RFICDTC=;
run;

/* ISS-attriblength must NOT regress: length=$ on the same group still types char. */
data L;
  attrib SITEID length=$10 label="Site";
  SITEID="S001";
  output;
run;
proc contents data=L; run;
