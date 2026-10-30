/* GAP-weekufn: SAS 9.4 documents WEEKU/WEEKW as WEEK formats/informats and
   INTCK/INTNX intervals, not as standalone functions. Keep typo/Viya-only
   calls loud instead of computing a plausible silent superset.
   expect-rc: 1 */
data _null_;
  u = weeku('04jul2020'd);
  w = weekw('04jul2020'd);
run;
