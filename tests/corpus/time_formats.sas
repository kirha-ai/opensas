/* GAP-timeformats: HHMM / HOUR / MINUTE / SECOND / E8601TM / E8601DN / BINARY.
   t=45000s = 12:30:00. dt=1893501000 = 01JAN2020:12:30:00 (SAS datetime). */
data _null_;
  t = 45000;
  put t hhmm.;       /* 12:30            */
  put t hour.;       /* 13  (integer hour, ROUNDED on minutes: 12:30 -> 13) */
  put t hour8.1;     /* 12.5 (decimal hours), width 8 */
  put t minute.;     /* 30 */
  put t second.;     /* 0  (width 2, blank-padded) */
  put t e8601tm.;    /* 12:30:00 */
  b = 5;
  put b binary8.;    /* 00000101 */
  dt = 1893501000;
  put dt e8601dn.;   /* 2020-01-01 (date part of the datetime) */
run;
