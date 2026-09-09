/* GAP-dtformats: DT-prefixed formats write the DATE part of a SAS DATETIME value
   (seconds since 1960), unlike DATE/MONYY/YEAR which take a date (days). Before the
   fix these errored "format not found" (exit 1). SAS 9.4: "DTDATEw./DTMONYYw./
   DTYEARw./DTWKDATXw. write the date part of a SAS datetime value." 01JAN2020
   12:30:00 = SAS day 21915 * 86400 + 45000; the time part must be dropped. */
data _null_;
  dt = 21915*86400 + 45000;
  put 'dtdate9  =' dt dtdate9.;
  put 'dtdate7  =' dt dtdate7.;
  put 'dtmonyy7 =' dt dtmonyy7.;
  put 'dtyear4  =' dt dtyear4.;
  put 'dtwkdatx =' dt dtwkdatx.;
run;
