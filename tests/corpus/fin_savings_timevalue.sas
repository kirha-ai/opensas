/* BUG-savingstv: SAVINGS/TIMEVALUE are correct on the SAS doc-exact signatures
   (date/rate schedule; rate as a percentage). QA's flat-rate repro was malformed. */
data _null_;
  tv = timevalue("01jan2001"d, "01jan2000"d, 1000, "MONTH", "01jan2000"d, 10);
  sv = savings("01jan2005"d, "01jan2000"d, 300, 24, "MONTH", "QUARTER", "01jan2000"d, 4.00);
  cp = compound(1000, ., 0.10, 5);
  put "tv=" tv 12.7;
  put "sv=" sv 12.6;
  put "cp=" cp 10.2;
run;
