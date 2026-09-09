/* >4096 obs with large magnitudes: quantiles must use ALL rows (not a capped
   4096-row prefix), and wide moment values (USS ~4e10) must not overflow the
   fixed-width padding. Regression for BUG-univarpctl4k / BUG-univarpad. */
data d;
  do i = 1 to 5000;
    x = i;
    output;
  end;
run;
proc univariate data=d;
  var x;
run;
