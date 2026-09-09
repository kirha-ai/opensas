/* %do with %by: descending negative step and a non-unit positive step. Synthetic. corpus-macroedge. */
%macro countdown;
  %do i = 10 %to 2 %by -2;
    data _null_; put "down=&i"; run;
  %end;
  %do j = 0 %to 9 %by 3;
    data _null_; put "up=&j"; run;
  %end;
%mend;
%countdown
