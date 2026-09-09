/* BUG-upcaseformat: $UPCASEw./$LOWCASEw. as WRITE formats transform case (the
   informat side existed; the format side leaked the original case). */
data _null_;
  a = put('abc', $upcase.);  put a=;
  b = put('AbC', $upcase3.); put b=;
  c = put('ABC', $lowcase.); put c=;
  d = put('abc', $upcase8.); put "[" d "]";
run;
