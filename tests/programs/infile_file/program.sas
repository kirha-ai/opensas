/*=============================================================================
* INFILE + FILE external text I/O: read a delimited text file line by line,
* then write each record back out through a FILE destination (a round trip).
*============================================================================*/
data _null_;
  infile "inputs/people.txt" dlm="," ;
  input name $ age;
  length line $40;
  line = catx(",", name, age);
  file "output/people.csv";
  put line;
run;
