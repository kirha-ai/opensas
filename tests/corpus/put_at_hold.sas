/* GAP-putptrslice: the trailing `@` output line hold is valid SAS 9.4
   (Statements Table 2.5 line-hold specifiers) opensas doesn't implement — a
   gap, so D-009's rc is 2 ("file an opensas issue"), not 1 ("fix your SAS").
   The ERROR names the construct on stderr; stdout stays empty. The sibling
   `@@` was already rc 2 (GAP-gapsexitingone) — one rc for one family.
   expect-rc: 2 */
data _null_;
  a = 1;
  put a @;
run;
