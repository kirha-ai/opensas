/* BUG-marginunit-suffix: numeric page-margin values can carry the SAS 9.4
   physical suffixes IN and CM. The unit lexes as a NAME after the NUMBER;
   skipOptionValue must consume it as part of the inert system option value, not
   treat it as an unknown system option. MM/PT rejection is pinned in main.zig. */
options leftmargin=0.5in rightmargin=1cm topmargin=2IN bottommargin=3CM;

data _null_;
  put "margin unit options accepted";
run;
