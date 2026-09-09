/* w.d informat applies an implied decimal; width truncates the field */
data d;
  a = input("12345", 5.2);
  b = input("123456", 4.);
  c = input("00042", 3.);
  put "a=" a " b=" b " c=" c;
run;
