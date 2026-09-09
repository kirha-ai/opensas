/* GAP-puttildemodifier — a `^` in PUT's modifier slot is NOT the documented
   `~` modifier and not any other PUT construct: it is the USER's typo, exit 1
   via the untouched "unexpected item in put statement" catch-all. The lexer
   maps both bytes to .caret but now keeps the source byte in `text`, so the
   parser can hold the two apart (D-018). Gap twin: rc_put_tilde_modifier.sas.
   expect-rc: 1 */
data _null_;
  x = 2353.2;
  put x ^ comma10.2;
run;
