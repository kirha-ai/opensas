/* HOUR-rounding: HOURw. (d=0) ROUNDS on the fractional hour (minutes), per SAS
   9.4 Formats and Informats: Reference, HOURw.d: "SAS rounds hours based on the
   value of minutes". The 11:30 row keeps the manual's argument because its
   printed result (12) is the oracle for the half-hour tie; the other rows are
   invented boundaries. */
data _null_;
  up   = 59400;       /* 16:30:00 -> rounds up   */
  put up hour.;       /* 17 */
  even = 36000;       /* 10:00:00 -> no rounding */
  put even hour.;     /* 10 */
  tie  = 41400;       /* 11:30:00 -> .5 rounds up (manual anchor) */
  put tie hour.;      /* 12 */
  down = 55740;       /* 15:29:00 -> rounds down */
  put down hour.;     /* 15 */
  dec  = 59400;       /* decimal form keeps the fraction, no d=0 rounding */
  put dec hour8.1;    /* 16.5 */
run;
