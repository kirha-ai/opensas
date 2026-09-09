/* GAP-inputcoldecimal F10: column input's trailing `.decimals` parameter —
   `input x 1-5 .2;` reads columns 1-5 and divides by 10^2 when the field holds
   no explicit decimal point — is VALID SAS 9.4 (SAS 9.4 DATA Step Statements:
   Reference, INPUT Statement: Column, printed p.183: ".decimals specifies the
   power of 10 by which to divide the value. If the data contains decimal
   points, the .decimals value is ignored."). opensas does not implement it
   (applying the divisor is read-path work), so it refuses LOUD as a NAMED
   rc-2 gap (D-009/D-009b(i)):
     input: the column-input .decimals parameter (input x 1-5 .2;) is not supported
   — never the old rc-1 "expected ';' after input" that blamed punctuation.
   expect-rc: 2 */
data d;
  input x 1-5 .2;
  datalines;
12345
;
run;
