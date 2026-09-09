/* GH#51 ISS-retainseedall (corrects GH#43): a single trailing initial value
   after several vars seeds ALL vars in the group, not just the first.
   `retain a b 'NEOPLASMS'` → a=b='NEOPLASMS' ; `retain c d e 5` → c=d=e=5. */
data t;
  length a b $40;
  retain a b 'NEOPLASMS';
  retain c d e 5;
  x = 1;
  output;
run;

proc print data=t; run;
