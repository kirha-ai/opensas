/* BUG-datdifbasis: an unsupported day-count basis fails loud — the value goes
   missing and a NOTE hits the log — instead of silently defaulting to ACT/ACT.
   Valid bases (datdif: ACT/ACT, 30/360; yrdif: + ACT/360, ACT/365, AGE) and
   the blank→ACT/ACT default are unchanged. */
data _null_;
  d30  = datdif("31JAN2020"d, "31MAR2020"d, "30/360");   /* valid: 60 */
  y360 = yrdif("01JAN2021"d, "01APR2021"d, "ACT/360");   /* valid YRDIF basis: 0.25 */
  ddef = datdif("01JAN2020"d, "01JUL2020"d, "");          /* blank → ACT/ACT: 182 */
  bad1 = datdif("01JAN2020"d, "01JUL2020"d, "ACT/360");   /* NOT a DATDIF basis */
  bad2 = datdif("01JAN2020"d, "01JUL2020"d, "GARBAGE");
  bad3 = yrdif("01JAN2020"d, "01JUL2020"d, "GARBAGE");
  put d30= y360= ddef= bad1= bad2= bad3=;
run;
