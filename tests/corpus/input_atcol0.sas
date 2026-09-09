/* BUG-atcol0crash: `@0` column pointer (and any @<1) is clamped to column 1,
   matching SAS — previously panicked with a usize underflow at io.zig `col-1`. */
data a;
  input @0 x 3.;
  put "x=" x;
datalines;
123
;
run;
