/* GAP-putptrslice: `@numeric-variable` is a valid SAS 9.4 PUT column pointer
   (Statements p.269, Table 2.5) opensas doesn't implement — a gap → rc 2.
   `@(a)` is the supported spelling of the same thing (GAP-atexpression-put).
   expect-rc: 2 */
data _null_;
  a = 15;
  put @a name $10.;
run;
