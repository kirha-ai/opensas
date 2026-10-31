/* NOTE-arrayparenput: SAS 9.4 PUT Statement, Arrays: array subscripts may be
   enclosed in braces, brackets, or parentheses for named and list output.
   Real SAS 9.4 probe accepted every form below, including a whole-array
   asterisk and a grouped-format control. */
data _null_;
  array a{3} a1-a3 (11 22 33);
  put 'paren ' a(2)=;
  put 'bracket ' a[2]=;
  put 'brace ' a{2}=;
  put 'whole ' a(*);
  put (a1 a2)(=);
run;
