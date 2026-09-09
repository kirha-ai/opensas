data _null_;
  x = .K;
  eq_q = (x = '.K');
  in_q = (x in ('.' '.A' '.D' '.K'));
  eq_l = (x = .K);
  ne_plain = (x = '.');
  put "eq_quoted=" eq_q "  in_quoted=" in_q "  eq_literal_control=" eq_l "  ne_plain=" ne_plain;
run;
