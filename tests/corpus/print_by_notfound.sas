/* BUG-byvarnotfound: PROC PRINT `by <missing-var>;` used to be silently
   ignored (flat section, empty BY line, rc 0). Now a BY variable that is not
   a column of the input dataset is a loud user ERROR ("Variable NOSUCH not
   found." — to stderr, like VAR/SUM/ID not-found), and the step prints
   nothing. A partially-valid list (`by g nosuch;`) fails on NOSUCH instead of
   silently grouping by g alone. Valid BY still sections (listing below).
   expect-rc: 1 */
data d;
  do g = 1 to 2;
    do i = 1 to 2;
      x = g * 10 + i;
      output;
    end;
  end;
  drop i;
run;

/* valid BY — unchanged: one section per group */
proc print data=d; by g; run;

/* unknown BY var → ERROR, no listing */
proc print data=d; by nosuch; run;

/* partially valid → ERROR on NOSUCH, no listing */
proc print data=d; by g nosuch; run;
