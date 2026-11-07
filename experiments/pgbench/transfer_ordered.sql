\set d random(0,1)
\if :d = 0
SELECT lab.transfer_ordered('alice','bob',1);
\else
SELECT lab.transfer_ordered('bob','alice',1);
\endif
