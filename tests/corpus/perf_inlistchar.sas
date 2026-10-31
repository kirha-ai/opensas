/* PERF-inlistchar: character IN/NOT IN sets use blank-padded equality. */
data _null_;
  length c $ 12;
  c = 'B   ';
  hit = c in ('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H');
  nothit = c not in ('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H');
  put 'trailing=' hit nothit;

  c = ' B';
  hit = c in ('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H');
  put 'leading=' hit;

  c = '';
  hit = c in ('A', 'B', 'C', 'D', 'E', 'F', 'G', ' ');
  nothit = c not in ('A', 'B', 'C', 'D', 'E', 'F', 'G', ' ');
  put 'blank=' hit nothit;

  c = 'H';
  hit = c in ('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H   ');
  put 'literalpad=' hit;

  c = 'b';
  hit = c in ('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H');
  put 'case=' hit;
run;
