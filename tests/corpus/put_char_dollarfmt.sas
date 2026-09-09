/* BUG-putcharfmt: $w.d dollar-width character formats in put()/input(). These
   ParseError'd 'expected an expression' because tryInformatSpec required $ + NAME
   (e.g. $char10.), not $ + width ($10.). The $-width form is ubiquitous in SDTM
   (`put(VFQxxx, $100.)`). */
data _null_;
  x = "hi";
  a = put(x, $6.);          /* char, right-padded to width 6 */
  b = input("abc", $8.);    /* $ char informat -> "abc" */
  c = put("clin", $char8.); /* named form still works */
  put "a=[" a "]";
  put "b=[" b "]";
  put "c=[" c "]";
run;
