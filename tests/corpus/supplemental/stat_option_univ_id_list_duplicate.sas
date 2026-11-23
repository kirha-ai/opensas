data sample;input g1 g2 g3 id1 $ id3 $ id2 $ x;datalines;
1 2 1 A C B 1
2 2 1 D F E 3
1 1 2 G I H 8
1 . 3 J L K 4
;
run;
ods select ExtremeObs;proc univariate data=sample nextrobs=1;id id1 id1;var x;run;
