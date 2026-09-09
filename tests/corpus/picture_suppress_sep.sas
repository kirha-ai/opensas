/* BUG-picturesep: in the leading SUPPRESSED region of a `0`-selector PICTURE
   (leading digit selectors blanked because the value is small), SAS also
   blanks interspersed MESSAGE chars (commas) and slides PREFIX= up against
   the first significant digit instead of pinning it to the field start.
   cm on 42 → `       42` (was ` ,   , 42`); pfx on 5 → `  $5` (was `$  5`).
   NINE-selector templates zero-FILL (never suppressed) and are unchanged:
   m on 42 → `$000,042`. A value filling past the separators is unchanged. */
proc format;
  picture cm  low-high='0,000,000';
  picture pfx low-high='000' (prefix='$');
  picture m   low-high='999,999' (prefix='$');
run;
data _null_;
  put 42 cm.;
  put 5 pfx.;
  put 42 m.;
  put 1234567 cm.;
run;
