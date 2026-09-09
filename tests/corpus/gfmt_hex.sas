/* hex_format: HEXw. (numeric integer part) and $HEXw. (per-byte char). Phase-G. */
data _null_;
  d = 22100; s = "AB";
  put "HEX="     d hex4.;
  put "HEXchar=" s $hex4.;
run;
