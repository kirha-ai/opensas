/* BUG-timezeropad: TIMEw. BLANK-pads a single-digit leading hour (SAS), not
   zero-pad — matching the TIMEAMPM/HHMM siblings. The blank/unpadded hour also
   lets the seconds fit at TIME7 (a zero-padded "01:01:01" would overflow and
   drop them). E8601TM is ISO 8601, so its hour STAYS zero-padded. */
data _null_;
  am  = '09:05:00't;
  one = '01:01:01't;
  two = '14:30:00't;
  mid = '00:00:00't;
  put am time8.;      /* " 9:05:00" — leading blank, not "09:05:00" */
  put one time7.;     /* "1:01:01"  — 7 chars, seconds present, not "  01:01" */
  put two time8.;     /* "14:30:00" — two-digit hour unchanged */
  put mid time8.;     /* " 0:00:00" — blank + single 0 */
  put am e8601tm.;    /* "09:05:00" — ISO keeps the zero-padded hour */
run;
