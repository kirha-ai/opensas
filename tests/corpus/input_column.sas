data _null_;
  input @1 name $5. @7 age 3. +1 score 5.2;
  put "name=" name " age=" age " score=" score;
  datalines;
Alice 042 12345
;
run;
