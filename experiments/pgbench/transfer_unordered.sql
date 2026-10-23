\set d random(0,1)
\if :d = 0
SELECT lab.transfer_unordered('alice','bob',1);
\else
SELECT lab.transfer_unordered('bob','alice',1);
\endif
