/* BUG-marginunit-suffix: numeric page-margin values can carry a physical unit
   suffix (`0.5in`). The unit lexes as a NAME after the NUMBER; skipOptionValue
   must consume it as part of the inert system option value, not treat it as an
   unknown system option. */
options leftmargin=0.5in rightmargin=1cm topmargin=5mm bottommargin=12pt;

data _null_;
  put "margin unit options accepted";
run;
