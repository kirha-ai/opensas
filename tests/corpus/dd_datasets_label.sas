data ae;
  usubjid="S01"; aeterm="Headache"; run;
proc datasets library=work nolist;
  modify ae (label='Adverse Events');
quit;
proc contents data=ae; run;
