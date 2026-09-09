/* BUG-picturedecimal: a PICTURE with a decimal point and no explicit MULT=
   defaults the multiplier to 10^(digit selectors after the '.'), so the
   fractional part fills the trailing selectors (SAS 9.4). Was rounding the
   value to an integer → digits landed in the wrong selectors. */
proc format;
  picture money low-high='0009.99';
run;
data _null_;
  do x = 12.5, 1234.5, 7;
    put x money.;
  end;
run;
