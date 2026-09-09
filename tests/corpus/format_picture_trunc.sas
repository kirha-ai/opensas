/* BUG-picturetrunc: SAS 9.4 TRUNCATES the scaled value by default — rounding is
   opt-in via the PICTURE (round) option. opensas rounded, so the last digit was
   wrong: 12.35 → `  12.4` (SAS `  12.3`), 99.99 → ` 100.0` (SAS `  99.9`). */
proc format;
  picture p low-high='0000.0';
  picture q low-high='00009' (mult=100);  /* explicit MULT= truncates too */
run;
data _null_;
  do x = 12.35, 99.99, 12.5, 7;
    put x p.;
  end;
  y = 12.999;
  put y q.;   /* 12.999×100 = 1299.9 → truncated 1299 → ` 1299` */
run;
