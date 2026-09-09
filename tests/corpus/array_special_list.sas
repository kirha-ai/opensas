/* GH#48 ISS-arrayspeciallist: `array v{*} _character_ / _numeric_ / _all_` must
   expand against the PDV — dim() = count of matching vars, and v[i] writes must
   bind to the real variables. Was a silent no-op: dim=1, writes hit a phantom. */
data _null_;
  length a b c $5; a='.'; b='x'; c='.';
  array v {*} _character_;
  n = dim(v);
  do i = 1 to dim(v); if strip(v[i]) = '.' then v[i] = ''; end;
  put "dim=" n " a=[" a "] b=[" b "] c=[" c "]";
run;

data _null_;
  x = 1; y = 2; z = 3;
  array w {*} _numeric_;
  do i = 1 to 3; w[i] = w[i] * 10; end;
  put x= y= z=;
run;
