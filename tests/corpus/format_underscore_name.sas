/* QA-svvisnum: a format NAME with underscores (a CNTLIN codelist format like
   VISNUM_ALL_PERIOD) was truncated at the first `_` by parseSpec — read as
   "format not found". Trailing digits are the width; underscores are part of the
   name, so both numeric and char underscore-named formats must resolve. */
proc format;
  value  NUM_GRP_CODE   1="one" 2="two";
  value $CHAR_GRP_CODE  "A"="Apple" "B"="Banana";
run;
data _null_;
  n = put(2, NUM_GRP_CODE.);
  c = put("A", $CHAR_GRP_CODE.);
  put "n=[" n "]";
  put "c=[" c "]";
run;
