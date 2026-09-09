/* Nested %do loops (2-level grid) — inner counter reset each outer pass. Synthetic. corpus-macroedge. */
%macro grid(rows, cols);
  %do r = 1 %to &rows;
    %do c = 1 %to &cols;
      data _null_; put "cell &r.,&c"; run;
    %end;
  %end;
%mend;
%grid(2, 3)
