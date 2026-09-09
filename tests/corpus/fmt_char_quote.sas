/* BUG-charfmtsink: $QUOTE wraps the value in double quotes (was a silent sink
   that leaked the raw value with no quotes). $UPCASE/$CHAR/plain $w. unchanged. */
data _null_;
  s = 'Hi';
  put "quote8:  [" s $quote8. "]";
  put "quote.:  [" s $quote. "]";
  put "upcase:  [" s $upcase8. "]";
  put "char4:   [" s $char4. "]";
  put "plain8:  [" s $8. "]";
run;
