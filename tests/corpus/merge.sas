data one;
  input id name $;
  datalines;
1 Alice
2 Bob
3 Carol
;
run;

data two;
  input id age;
  datalines;
1 30
2 25
3 40
;
run;

data _null_;
  merge one two;
  by id;
  put "id=" id " name=" name " age=" age;
run;
