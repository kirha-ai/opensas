/* BUG-retaininitspecialmiss: a special-missing initial value (`.A`-`.Z`/`._`)
   in RETAIN is retained as that special missing — not parsed as plain `.` plus
   a phantom variable of the letter's name. `retain x .A t 1 u .B;` yields exactly
   three columns x/t/u (no spurious A or B). */
data a;
  retain x .A t 1 u .B;
  output; stop;
run;
proc print data=a; run;
