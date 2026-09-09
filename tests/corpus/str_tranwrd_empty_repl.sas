/* tranwrd(): a blank/empty 3rd arg is treated as a single blank, NOT ""
   — SAS 9.4 data-cleaning gotcha. Removing a char needs compress(), not
   tranwrd(...,""). Locks the surprising-but-correct behavior. */
data _null_;
  gotcha = tranwrd("a-b-c", "-", "");    /* -> "a b c" (blank, not removal) */
  right  = compress("a-b-c", "-");       /* -> "abc"   (actual removal)      */
  put "gotcha=[" gotcha "]";
  put "right=[" right "]";
run;
