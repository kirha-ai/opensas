/* EBNF-closeout: the generic format_ref grammar ([$] name [w] . [d]) resolves
   a $-prefixed user format, a built-in DOLLARw.d, and a bare w.d — proving the
   production opensas now annotates. */
proc format;
  value $sex "M"="Male" "F"="Female";
run;
data _null_;
  length s $10;
  s = put("F", $sex.);
  d = put(1234.5, dollar10.2);
  w = put(3.14159, 8.3);
  put "USERFMT=[" s "]";
  put "DOLLAR=[" d "]";
  put "WD=[" w "]";
run;
