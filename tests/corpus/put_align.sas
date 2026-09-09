/* GAP-putalign: PUT `-R` / `-L` right/left-justify a value within its format
   width. Numeric defaults right; char defaults left; the modifier flips it. */
data _null_;
  n = 42;
  c = "AB";
  /* numeric within width 6: default right, -L pushes it left */
  put "[" n 6. "]";
  put "[" n 6. -L "]";
  /* char within width 6: default left, -R pushes it right */
  put "[" c $6. "]";
  put "[" c $6. -R "]";
run;
