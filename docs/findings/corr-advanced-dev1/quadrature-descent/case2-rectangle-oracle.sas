options linesize=240 pagesize=max;
proc iml;
params={-.4956306291470207 .8088444041132948 .2855878655411077 .9947335197981,
        -.495630632452179 .8088444028834387 .2855878638305473 .9950991078001906};
counts={280 0,273 161,0 189};
do state=1 to 2;
 x=-40//params[state,1:2]`//40;y=-40//params[state,3]//40;r=params[state,4];p=j(3,2,0);
 do i=1 to 3;do j=1 to 2;
  p[i,j]=probbnrm(x[i+1],y[j+1],r)-probbnrm(x[i],y[j+1],r)-probbnrm(x[i+1],y[j],r)+probbnrm(x[i],y[j],r);
 end;end;
 total=sum(p);nll=0;
 do i=1 to 3;do j=1 to 2;if counts[i,j]>0 then nll=nll-counts[i,j]*log(p[i,j]);end;end;
 print state p[format=best32.] total[format=best32.] nll[format=best32.];
end;
quit;
