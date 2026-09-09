/* GAP-charlength: declared char LENGTHs truncate assignments, as in SAS.
   Three routes: the LENGTH statement (parse-time), the dotted ATTRIB form
   `length=$11.` the EMPTY_* metadata macro emits (was silently DROPPED -> no
   width anywhere), and a width carried in from a zero-row SET source's schema
   (only enforceable at runtime, pdv.set). */
data t;
  attrib u length=$11.;
  length v $4;
  u = "Other - STIMULATION";
  v = "LONGTEXT";
  put u= v=;
run;

data empty;
  length w $5;
  delete;
run;
data rows;
  k = 1;
run;
data s;
  set empty rows;
  w = "TOOLONGVALUE";
  put w=;
run;
