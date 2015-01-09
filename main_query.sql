USE [momo]
GO

-------------------------------------------------------------------------------------------- pre-execute
IF Object_id('tempdb..#mpcpromotable') IS NOT NULL 
  BEGIN 
      DROP TABLE #mpcpromotable 
  END 

CREATE TABLE #mpcpromotable 
  ( 
     count     INT, 
     goodscode CHAR(30), 
     catecode  CHAR(30), 
     p2code    CHAR(30), 
     promotype INT 
  ); 

-- left join mpc within discounting table  
INSERT INTO #mpcpromotable 
SELECT mpc.count, 
       mpc.goods_code, 
       mpc.category_code, 
       mpc.p2_category_code, 
       CASE 
         WHEN promo.goods_code IS NULL THEN 1 
         ELSE 0 
       END AS promotype 
FROM   fg.dbo.userprefer_goodscateg2count_mpc AS mpc 
       LEFT JOIN fg.dbo.promo_detail AS promo 
              ON promo.goods_code = mpc.goods_code; 

IF Object_id('tempdb..#filledtwishp0p2') IS NOT NULL 
  BEGIN 
      DROP TABLE #filledtwishp0p2 
  END 

CREATE TABLE #filledtwishp0p2 
  ( 
     custno    CHAR(30), 
     goodscode CHAR(30), 
     catecode  CHAR(30), 
     p2code    CHAR(30) 
  ); 

-- fill p2 value in twish; 00:02, 836269  
INSERT INTO #filledtwishp0p2 
SELECT twish.cust_no, 
       twish.goods_code, 
       twish.category_code, 
       cate2p2map.p2_category_code 
FROM   momo.dbo.twishlist AS twish 
       JOIN (SELECT twcate.category_code, 
                    mpcate.p2_category_code 
             FROM   (SELECT twish.category_code 
                     FROM   momo.dbo.twishlist AS twish 
                     GROUP  BY twish.category_code) AS twcate 
                    JOIN (SELECT mpc.category_code, 
                                 mpc.p2_category_code 
                          FROM   fg.dbo.userprefer_goodscateg2count_mpc AS mpc
                          GROUP  BY mpc.category_code, 
                                    mpc.p2_category_code) AS mpcate 
                      ON twcate.category_code = mpcate.category_code) AS
            cate2p2map 
         ON cate2p2map.category_code = twish.category_code 
ORDER  BY cust_no 

-- fill p0 and p2 value in twish; 00:00, 68998  
INSERT INTO #filledtwishp0p2 
SELECT result.cust_no, 
       result.goods_code, 
       result.category_code, 
       result.p2_category_code 
FROM   (SELECT twish.cust_no, 
               twish.goods_code, 
               tpindex.category_code, 
               tpindex.p2_category_code, 
               Row_number() 
                 OVER( 
                   partition BY twish.cust_no, twish.goods_code 
                   ORDER BY twish.cust_no ASC) AS Row1 
        FROM   momo.dbo.twishlist AS twish 
               JOIN (SELECT twgoodcode.goods_code, 
                            mpcate.category_code, 
                            mpcate.p2_category_code 
                     FROM   (SELECT twish.goods_code 
                             FROM   momo.dbo.twishlist AS twish 
                             WHERE  twish.category_code IS NULL 
                             GROUP  BY twish.goods_code) AS twgoodcode
                            JOIN (SELECT mpc.goods_code, 
                                         mpc.category_code, 
                                         mpc.p2_category_code 
                                  FROM   fg.dbo.userprefer_goodscateg2count_mpc
                                         AS mpc 
                                  GROUP  BY mpc.goods_code, 
                                            mpc.category_code, 
                                            mpc.p2_category_code) AS mpcate
                              ON twgoodcode.goods_code = mpcate.goods_code) AS
                    tpindex 
                 ON tpindex.goods_code = twish.goods_code 
                    AND twish.category_code IS NULL) AS result 
WHERE  result.row1 = 1; 

-- 190703  
--select count(custno) from #filledtwishp0p2 group by custno;  
-- 194432  
--select count(CUST_NO) from momo.dbo.twishlist group by CUST_NO;  
-- 881818  
--select distinct * from #filledtwishp0p2 order by custno;  
-- 943996  
--select distinct * from momo.dbo.twishlist order by CUST_NO;  
IF Object_id('tempdb..#ardiscount') IS NOT NULL 
  BEGIN 
      DROP TABLE #ardiscount 
  END 

CREATE TABLE #ardiscount 
  ( 
     cust_no      CHAR(30), 
     goodscode    CHAR(30), 
     catecode     CHAR(30), 
     recomdlist   CHAR(30), 
     importance   NVARCHAR(max), 
     discounttype INT 
  ); 

INSERT INTO #ardiscount 
SELECT aa.custno, 
       aa.goodscode, 
       aa.catecode, 
       aa.recomd_list, 
       aa.node_importance, 
       1 
FROM   (SELECT twish.custno, 
               twish.goodscode, 
               twish.catecode, 
               ar1.recomd_list, 
               ar1.node_importance 
        FROM   #filledtwishp0p2 AS twish 
               LEFT JOIN fg.dbo.cache_assocorder_i2i AS ar1 
                      ON twish.goodscode = ar1.goods_code 
                         AND ar1.recomd_list IS NOT NULL) AS aa 
WHERE  aa.recomd_list IN (SELECT mpc.goodscode 
                          FROM   #mpcpromotable AS mpc 
                          WHERE  mpc.promotype = 1) 
UNION 
SELECT bb.custno, 
       bb.goodscode, 
       bb.catecode, 
       bb.recomd_list, 
       bb.node_importance, 
       5 
FROM   (SELECT twish.custno, 
               twish.goodscode, 
               twish.catecode, 
               ar1.recomd_list, 
               ar1.node_importance 
        FROM   #filledtwishp0p2 AS twish 
               LEFT JOIN fg.dbo.cache_assocorder_i2i AS ar1 
                      ON twish.goodscode = ar1.goods_code 
                         AND ar1.recomd_list IS NOT NULL) AS bb 
WHERE  bb.recomd_list IN (SELECT mpc.goodscode 
                          FROM   #mpcpromotable AS mpc 
                          WHERE  mpc.promotype = 0) 
UNION 
SELECT cc.custno, 
       cc.goodscode, 
       cc.catecode, 
       cc.rec_icode, 
       cc.importance, 
       2 
FROM   (SELECT twish.custno, 
               twish.goodscode, 
               twish.catecode, 
               ar2.rec_icode, 
               ar2.importance 
        FROM   #filledtwishp0p2 AS twish 
               LEFT JOIN fg.dbo.accumassocrule_recomdlog AS ar2 
                      ON twish.goodscode = ar2.icode 
                         AND ar2.rec_icode IS NOT NULL) AS cc 
WHERE  cc.rec_icode IN (SELECT mpc.goodscode 
                        FROM   #mpcpromotable AS mpc 
                        WHERE  mpc.promotype = 1) 
UNION 
SELECT cc.custno, 
       cc.goodscode, 
       cc.catecode, 
       cc.rec_icode, 
       cc.importance, 
       6 
FROM   (SELECT twish.custno, 
               twish.goodscode, 
               twish.catecode, 
               ar2.rec_icode, 
               ar2.importance 
        FROM   #filledtwishp0p2 AS twish 
               LEFT JOIN fg.dbo.accumassocrule_recomdlog AS ar2 
                      ON twish.goodscode = ar2.icode 
                         AND ar2.rec_icode IS NOT NULL) AS cc 
WHERE  cc.rec_icode IN (SELECT mpc.goodscode 
                        FROM   #mpcpromotable AS mpc 
                        WHERE  mpc.promotype = 0); 

-- 02:49 -- 
--select mpc.catecode, mpc.goodscode from #filledtwishp0p2 as twish left join #mpcpromotable as mpc on mpc.catecode = twish.CATEGORY_CODE and mpc.promotype = 1 order by mpc.catecode, mpc.goodscode;
IF Object_id('tempdb..#tpdiscount') IS NOT NULL 
  BEGIN 
      DROP TABLE #tpdiscount; 
  END 

CREATE TABLE #tpdiscount 
  ( 
     cust_no      CHAR(30), 
     catecode     CHAR(30), 
     recomdlist   CHAR(30), 
     discounttype INT 
  ); 

IF Object_id('tempdb..#tpbinding') IS NOT NULL 
  BEGIN 
      DROP TABLE #tpbinding; 
  END 

CREATE TABLE #tpbinding 
  ( 
     catecode     CHAR(30), 
     recomdlist   CHAR(30), 
     discounttype INT 
  ); 

-- grap p0 with its recomd items from #mpcpromotable 
insert into #tpbinding
select distinct result.catecode, result.goodscode, 3 from (
select mpc.catecode, mpc.goodscode, mpc.count,
 Row_number() 
                 OVER( 
                   partition BY mpc.catecode
                   ORDER BY mpc.count desc) AS Row1 
from (
select twish.catecode from #filledtwishp0p2 as twish group by twish.catecode) as twcate 
join #mpcpromotable as mpc on mpc.catecode = twcate.catecode where mpc.promotype = 1 ) as result where result.Row1 between 1 and 40
union
select distinct result.catecode, result.goodscode, 7 from (
select mpc.catecode, mpc.goodscode, mpc.count,
 Row_number() 
                 OVER( 
                   partition BY mpc.catecode
                   ORDER BY mpc.count desc) AS Row1 
from (
select twish.catecode from #filledtwishp0p2 as twish group by twish.catecode) as twcate 
join #mpcpromotable as mpc on mpc.catecode = twcate.catecode where mpc.promotype = 0 ) as result where result.Row1 between 1 and 40
union
select distinct result.p2code, result.goodscode, 4 from (
select mpc.p2code, mpc.goodscode, mpc.count,
 Row_number() 
                 OVER( 
                   partition BY mpc.p2code
                   ORDER BY mpc.count desc) AS Row1 
from (
select twish.p2code from #filledtwishp0p2 as twish group by twish.p2code) as twcate 
join #mpcpromotable as mpc on mpc.p2code = twcate.p2code where mpc.promotype = 1 ) as result where result.Row1 between 1 and 40
union
select distinct result.p2code, result.goodscode, 8 from (
select mpc.p2code, mpc.goodscode, mpc.count,
 Row_number() 
                 OVER( 
                   partition BY mpc.p2code
                   ORDER BY mpc.count desc) AS Row1 
from (
select twish.p2code from #filledtwishp0p2 as twish group by twish.p2code) as twcate 
join #mpcpromotable as mpc on mpc.p2code = twcate.p2code where mpc.promotype = 0 ) as result where result.Row1 between 1 and 40;

insert into #tpdiscount
select result.custno, result.catecode, result.items, result.discounttype from (
select twish.custno as custno, twish.goodscode as gcode, tp.catecode as catecode, tp.recomdlist as items, tp.discounttype as discounttype from #filledtwishp0p2 as twish join #tpbinding as tp on twish.catecode = tp.catecode and tp.discounttype = 3 ) as result where result.gcode != result.items
union
select result.custno, result.catecode, result.items, result.discounttype from (
select twish.custno as custno, twish.goodscode as gcode, tp.catecode as catecode, tp.recomdlist as items, tp.discounttype as discounttype from #filledtwishp0p2 as twish join #tpbinding as tp on twish.catecode = tp.catecode and tp.discounttype = 7 ) as result where result.gcode != result.items
union
select result.custno, result.catecode, result.items, result.discounttype from (
select twish.custno as custno, twish.goodscode as gcode, tp.catecode as catecode, tp.recomdlist as items, tp.discounttype as discounttype from #filledtwishp0p2 as twish join #tpbinding as tp on twish.p2code = tp.catecode and tp.discounttype = 4 ) as result where result.gcode != result.items
union
select result.custno, result.catecode, result.items, result.discounttype from (
select twish.custno as custno, twish.goodscode as gcode, tp.catecode as catecode, tp.recomdlist as items, tp.discounttype as discounttype from #filledtwishp0p2 as twish join #tpbinding as tp on twish.p2code = tp.catecode and tp.discounttype = 8 ) as result where result.gcode != result.items;

-- 05:52, 
IF OBJECT_ID('momo.dbo.CL_RecItemv4', 'U') IS NOT NULL
  DROP TABLE momo.dbo.CL_RecItemv4;
  CREATE TABLE momo.dbo.CL_RecItemv4(CustNO nvarchar(20), item nvarchar(max), type nvarchar(max));

-- , 3149710
insert into momo.dbo.CL_RecItemv4
select cust_no, recomdlist, discounttype from #ardiscount as artable group by cust_no, recomdlist, importance, discounttype order by cust_no asc, importance desc, discounttype asc;

-- , 40277148
insert into momo.dbo.CL_RecItemv4
select cust_no, recomdlist, discounttype from #tpdiscount as tptable group by cust_no, recomdlist, discounttype order by cust_no asc, discounttype asc;

-- get 40 items from each custno
IF OBJECT_ID('momo.dbo.CL_RedunceRecItemv4', 'U') IS NOT NULL
  DROP TABLE momo.dbo.CL_RedunceRecItemv4;
  CREATE TABLE momo.dbo.CL_RedunceRecItemv4(CustNO nvarchar(20), item nvarchar(max), type nvarchar(max));

insert into momo.dbo.CL_RedunceRecItemv4
select CustNO, item, type from (select CustNO, item, type, ROW_NUMBER() OVER(PARTITION BY CustNO ORDER BY type asc) AS Row from momo.dbo.CL_RecItemv4) as t  where Row between 1 and 40 order by CustNO, type;


IF OBJECT_ID('momo.dbo.CL_Resultv4', 'U') IS NOT NULL
  DROP TABLE momo.dbo.CL_Resultv4;
  CREATE TABLE momo.dbo.CL_Resultv4(CustNO nvarchar(20), Items nvarchar(max));

-- concate items into string
insert into momo.dbo.CL_Resultv4
SELECT distinct CAT.CustNO AS CustNO, STUFF(( SELECT  ',' + SUB.item AS [text()]
                        FROM momo.dbo.CL_RedunceRecItemv4 SUB
                        WHERE
                        SUB.CustNO = CAT.CustNO order by CustNO, type
                        FOR XML PATH('')), 1, 1, '' )
            AS [Items]
FROM  momo.dbo.CL_RedunceRecItemv4 CAT;

-------------------------------------------------------------------------------------------- start main process

-- above time: xmxs

-- below time: 48m55s

-- table_wishlist (881823)
-- 0m08s
IF Object_id('tempdb..#table_wishlist') IS NOT NULL
	DROP TABLE #table_wishlist
CREATE TABLE #table_wishlist(custno CHAR(30), goodscode CHAR(30), catecode CHAR(30), p2code CHAR(30))
INSERT INTO #table_wishlist
	SELECT DISTINCT * FROM #filledtwishp0p2

--------------------------------------------------------------------------------------------
-- table1 (89715) 8m24s
-- 1m38s
IF Object_id('tempdb..#table_1') IS NOT NULL
	DROP TABLE #table_1
CREATE TABLE #table_1(
	custno    CHAR(30),
	goodscode CHAR(30),
	catecode  CHAR(30),
	p2code    CHAR(30)
)
INSERT INTO #table_1
SELECT *
FROM #table_wishlist WHERE custno IN (
	SELECT custno
	FROM #table_wishlist
	GROUP BY custno
	HAVING COUNT(custno) = 1
)

-- table_1_result (6754743)
-- 2m39s
IF Object_id('tempdb..#table_1_result') IS NOT NULL
	DROP TABLE #table_1_result
CREATE TABLE #table_1_result(
	custno       CHAR(30),
	recomdlist   CHAR(30),
	discounttype INT,
	importance   NVARCHAR(max)
)
INSERT INTO #table_1_result
SELECT x1.custno, x2.recomdlist, x2.discounttype, x2.importance
FROM #table_1 AS x1
LEFT JOIN #ardiscount AS x2 ON x1.custno = x2.cust_no --333505-15689=317816
WHERE x2.recomdlist IS NOT NULL
UNION
SELECT x1.custno, x2.recomdlist, x2.discounttype, '0'
FROM #table_1 AS x1
LEFT JOIN #tpdiscount AS x2 ON x1.custno = x2.cust_no --6436927
WHERE x2.recomdlist IS NOT NULL

-- verify
--SELECT * FROM #table_1_result --6754743,1m10s
--SELECT DISTINCT * FROM #table_1_result --6754743,4m33s

-- table_1_result2 (3451788)
-- 4m41s
IF Object_id('tempdb..#table_1_result2') IS NOT NULL
	DROP TABLE #table_1_result2
CREATE TABLE #table_1_result2(
	custno       CHAR(30),
	recomdlist   CHAR(30),
	discounttype INT,
	importance   NVARCHAR(max)
)
INSERT INTO #table_1_result2
SELECT custno, recomdlist, discounttype, importance --3m33s
FROM(
	SELECT ROW_NUMBER() OVER(PARTITION BY custno ORDER BY discounttype, importance DESC) AS rowid, *
	FROM(
		SELECT * FROM( --6224843,2m53s
			SELECT ROW_NUMBER() OVER(PARTITION BY custno+','+recomdlist ORDER BY discounttype, importance DESC) AS rowid3, *
			FROM #table_1_result
		) AS t3
		WHERE rowid3 = 1
	) AS t2
) AS t1
WHERE rowid <= 40
ORDER BY discounttype, importance DESC

-- concat (89715)
-- 0m49s
/*SELECT T1.custno, COUNT(*) AS good_count, (STUFF((
	SELECT ',' + recomdlist
	FROM #table_1_result2 T2
	WHERE T2.custno = T1.custno
	FOR XML PATH('')), 1, 1, ''
)) AS t
FROM #table_1_result2 T1
GROUP BY custno
--HAVING COUNT(*) = 40 --bottleneck!!!
ORDER BY custno*/


--------------------------------------------------------------------------------------------
-- table2 (64936) 5m06s
-- 0m02s
IF Object_id('tempdb..#table_2') IS NOT NULL
	DROP TABLE #table_2
CREATE TABLE #table_2(
	custno    CHAR(30),
	goodscode CHAR(30),
	catecode  CHAR(30),
	p2code    CHAR(30),
	goodindex INT
)
INSERT INTO #table_2
SELECT *, ROW_NUMBER() OVER(PARTITION BY custno ORDER BY custno, goodscode, catecode, p2code)
FROM #table_wishlist WHERE custno IN (
	SELECT custno
	FROM #table_wishlist
	GROUP BY custno
	HAVING COUNT(custno) = 2
)

-- table_2_result (3111896)
-- 2m30s
IF Object_id('tempdb..#table_2_result') IS NOT NULL
	DROP TABLE #table_2_result
CREATE TABLE #table_2_result(
	custno       CHAR(30),
	recomdlist   CHAR(30),
	discounttype INT,
	importance   NVARCHAR(max),
	goodindex    INT
)
INSERT INTO #table_2_result
SELECT DISTINCT x1.custno, x2.recomdlist, x2.discounttype, x2.importance, x1.goodindex
FROM #table_2 AS x1
LEFT JOIN #ardiscount AS x2 ON x1.custno = x2.cust_no AND x1.goodscode = x2.goodscode --254543-11489=243054
WHERE x2.recomdlist IS NOT NULL
UNION
SELECT DISTINCT x1.custno, x2.recomdlist, x2.discounttype, '0', x1.goodindex
FROM #table_2 AS x1
LEFT JOIN #tpdiscount AS x2 ON x1.custno = x2.cust_no AND x1.catecode = x2.catecode --2869018-176=2868842
WHERE x2.recomdlist IS NOT NULL

-- verify
--SELECT * FROM #table_2_result --3111896,0m36s
--SELECT DISTINCT * FROM #table_2_result --3111896,0m41s

-- table_2_result2 (1207911)
-- 2m08s
IF Object_id('tempdb..#table_2_result2') IS NOT NULL
	DROP TABLE #table_2_result2
CREATE TABLE #table_2_result2(
	custno       CHAR(30),
	recomdlist   CHAR(30),
	discounttype INT,
	importance   NVARCHAR(max),
	goodindex    INT
)
INSERT INTO #table_2_result2
SELECT custno, recomdlist, discounttype, importance, goodindex --2m32s
FROM(
	SELECT ROW_NUMBER() OVER(PARTITION BY custno+','+CONVERT(nvarchar,goodindex) ORDER BY discounttype, importance DESC, goodindex, custno, recomdlist) AS rowid, *
	FROM(
		SELECT * FROM( --2951614,1m37s
			SELECT ROW_NUMBER() OVER(PARTITION BY custno+','+recomdlist+','+CONVERT(nvarchar,goodindex) ORDER BY discounttype, importance DESC) AS rowid3, *
			FROM #table_2_result --3111896,0m38s
		) AS t3
		WHERE rowid3 = 1
	) AS t2
) AS t1
WHERE rowid <= 20
ORDER BY discounttype, importance DESC

-- table_2_result3 (1101172)
-- 0m07s
IF Object_id('tempdb..#table_2_result3') IS NOT NULL
	DROP TABLE #table_2_result3
CREATE TABLE #table_2_result3(
	custno       CHAR(30),
	recomdlist   CHAR(30)
)
INSERT INTO #table_2_result3
SELECT custno, recomdlist --1h55m01s
FROM #table_2_result2
GROUP BY custno, recomdlist
ORDER BY MIN(discounttype), MAX(importance) DESC

-- concat (32468)
-- 0m19s
/*SELECT T1.custno, COUNT(*) AS good_count, (STUFF((
	SELECT ',' + recomdlist
	FROM #table_2_result3 T2
	WHERE T2.custno = T1.custno
	FOR XML PATH('')), 1, 1, ''
)) AS t
FROM #table_2_result3 T1
GROUP BY custno
--HAVING COUNT(*) = 40 --bottleneck!!!
ORDER BY custno*/


--------------------------------------------------------------------------------------------
-- table3 (50535) 3m58s
-- 0m01s
IF Object_id('tempdb..#table_3') IS NOT NULL
	DROP TABLE #table_3
CREATE TABLE #table_3(
	custno    CHAR(30),
	goodscode CHAR(30),
	catecode  CHAR(30),
	p2code    CHAR(30),
	goodindex INT
)
INSERT INTO #table_3
SELECT *, ROW_NUMBER() OVER(PARTITION BY custno ORDER BY custno, goodscode, catecode, p2code)
FROM #table_wishlist WHERE custno IN (
	SELECT custno
	FROM #table_wishlist
	GROUP BY custno
	HAVING COUNT(custno) = 3
)

-- table_3_result (2476086)
-- 2m02s
IF Object_id('tempdb..#table_3_result') IS NOT NULL
	DROP TABLE #table_3_result
CREATE TABLE #table_3_result(
	custno       CHAR(30),
	recomdlist   CHAR(30),
	discounttype INT,
	importance   NVARCHAR(max),
	goodindex    INT
)
INSERT INTO #table_3_result
SELECT DISTINCT x1.custno, x2.recomdlist, x2.discounttype, x2.importance, x1.goodindex
FROM #table_3 AS x1
LEFT JOIN #ardiscount AS x2 ON x1.custno = x2.cust_no AND x1.goodscode = x2.goodscode --254543-11489=243054 --202301-9455=192846
WHERE x2.recomdlist IS NOT NULL
UNION
SELECT DISTINCT x1.custno, x2.recomdlist, x2.discounttype, '0', x1.goodindex
FROM #table_3 AS x1
LEFT JOIN #tpdiscount AS x2 ON x1.custno = x2.cust_no AND x1.catecode = x2.catecode --2869018-176=2868842 --2283370-130=2283240
WHERE x2.recomdlist IS NOT NULL

-- verify
--SELECT * FROM #table_3_result --2476086,0m27s
--SELECT DISTINCT * FROM #table_3_result --2476086,0m34s

-- table_3_result2 (635124)
-- 1m40s
IF Object_id('tempdb..#table_3_result2') IS NOT NULL
	DROP TABLE #table_3_result2
CREATE TABLE #table_3_result2(
	custno       CHAR(30),
	recomdlist   CHAR(30),
	discounttype INT,
	importance   NVARCHAR(max),
	goodindex    INT
)
INSERT INTO #table_3_result2
SELECT custno, recomdlist, discounttype, importance, goodindex --1m42s
FROM(
	SELECT ROW_NUMBER() OVER(PARTITION BY custno+','+CONVERT(nvarchar,goodindex) ORDER BY discounttype, importance DESC, goodindex, custno, recomdlist) AS rowid, *
	FROM(
		SELECT * FROM( --2349964,1m18s
			SELECT ROW_NUMBER() OVER(PARTITION BY custno+','+recomdlist+','+CONVERT(nvarchar,goodindex) ORDER BY discounttype, importance DESC) AS rowid3, *
			FROM #table_3_result --2476086,0m30s
		) AS t3
		WHERE rowid3 = 1
	) AS t2
) AS t1
WHERE rowid <= 13
ORDER BY discounttype, importance DESC

-- table_3_result3 (563610)
-- 0m04s
IF Object_id('tempdb..#table_3_result3') IS NOT NULL
	DROP TABLE #table_3_result3
CREATE TABLE #table_3_result3(
	custno       CHAR(30),
	recomdlist   CHAR(30)
)
INSERT INTO #table_3_result3
SELECT custno, recomdlist --xhxxmxxs --xxxxxxxxxx
FROM #table_3_result2
GROUP BY custno, recomdlist
ORDER BY MIN(discounttype), MAX(importance) DESC

-- concat (16845)
-- 0m10s
/*SELECT T1.custno, COUNT(*) AS good_count, (STUFF((
	SELECT ',' + recomdlist
	FROM #table_3_result3 T2
	WHERE T2.custno = T1.custno
	FOR XML PATH('')), 1, 1, ''
)) AS t
FROM #table_3_result3 T1
GROUP BY custno
--HAVING COUNT(*) = 40 --bottleneck!!!
ORDER BY custno*/


--------------------------------------------------------------------------------------------
-- table4 (42252) 3m16s
-- 0m00s
IF Object_id('tempdb..#table_4') IS NOT NULL
	DROP TABLE #table_4
CREATE TABLE #table_4(
	custno    CHAR(30),
	goodscode CHAR(30),
	catecode  CHAR(30),
	p2code    CHAR(30),
	goodindex INT
)
INSERT INTO #table_4
SELECT *, ROW_NUMBER() OVER(PARTITION BY custno ORDER BY custno, goodscode, catecode, p2code)
FROM #table_wishlist WHERE custno IN (
	SELECT custno
	FROM #table_wishlist
	GROUP BY custno
	HAVING COUNT(custno) = 4
)

-- table_4_result (2093048)
-- 1m37s
IF Object_id('tempdb..#table_4_result') IS NOT NULL
	DROP TABLE #table_4_result
CREATE TABLE #table_4_result(
	custno       CHAR(30),
	recomdlist   CHAR(30),
	discounttype INT,
	importance   NVARCHAR(max),
	goodindex    INT
)
INSERT INTO #table_4_result
SELECT DISTINCT x1.custno, x2.recomdlist, x2.discounttype, x2.importance, x1.goodindex
FROM #table_4 AS x1
LEFT JOIN #ardiscount AS x2 ON x1.custno = x2.cust_no AND x1.goodscode = x2.goodscode --168586-8408=160178
WHERE x2.recomdlist IS NOT NULL
UNION
SELECT DISTINCT x1.custno, x2.recomdlist, x2.discounttype, '0', x1.goodindex
FROM #table_4 AS x1
LEFT JOIN #tpdiscount AS x2 ON x1.custno = x2.cust_no AND x1.catecode = x2.catecode --1932977-107=1932870
WHERE x2.recomdlist IS NOT NULL

-- verify
--SELECT * FROM #table_4_result --2093048,0m22s
--SELECT DISTINCT * FROM #table_4_result --2093048,0m28s

-- table_4_result2 (413750)
-- 1m19s
IF Object_id('tempdb..#table_4_result2') IS NOT NULL
	DROP TABLE #table_4_result2
CREATE TABLE #table_4_result2(
	custno       CHAR(30),
	recomdlist   CHAR(30),
	discounttype INT,
	importance   NVARCHAR(max),
	goodindex    INT
)
INSERT INTO #table_4_result2
SELECT custno, recomdlist, discounttype, importance, goodindex --1m23s
FROM(
	SELECT ROW_NUMBER() OVER(PARTITION BY custno+','+CONVERT(nvarchar,goodindex) ORDER BY discounttype, importance DESC, goodindex, custno, recomdlist) AS rowid, *
	FROM(
		SELECT * FROM( --1990104,1m04s
			SELECT ROW_NUMBER() OVER(PARTITION BY custno+','+recomdlist+','+CONVERT(nvarchar,goodindex) ORDER BY discounttype, importance DESC) AS rowid3, *
			FROM #table_4_result --2093048,0m25s
		) AS t3
		WHERE rowid3 = 1
	) AS t2
) AS t1
WHERE rowid <= 10
ORDER BY discounttype, importance DESC

-- table_4_result3 (363037)
-- 0m02s
IF Object_id('tempdb..#table_4_result3') IS NOT NULL
	DROP TABLE #table_4_result3
CREATE TABLE #table_4_result3(
	custno       CHAR(30),
	recomdlist   CHAR(30)
)
INSERT INTO #table_4_result3
SELECT custno, recomdlist --xhxxmxxs --xxxxxxxxxx
FROM #table_4_result2
GROUP BY custno, recomdlist
ORDER BY MIN(discounttype), MAX(importance) DESC

-- concat (10563)
-- 0m06s
/*SELECT T1.custno, COUNT(*) AS good_count, (STUFF((
	SELECT ',' + recomdlist
	FROM #table_4_result3 T2
	WHERE T2.custno = T1.custno
	FOR XML PATH('')), 1, 1, ''
)) AS t
FROM #table_4_result3 T1
GROUP BY custno
--HAVING COUNT(*) = 40 --bottleneck!!!
ORDER BY custno*/


--------------------------------------------------------------------------------------------
-- table5 (205560) 22m57s
-- 0m12s
IF Object_id('tempdb..#table_5') IS NOT NULL
	DROP TABLE #table_5
CREATE TABLE #table_5(
	custno    CHAR(30),
	goodscode CHAR(30),
	catecode  CHAR(30),
	p2code    CHAR(30),
	goodindex INT
)
INSERT INTO #table_5
SELECT * FROM(
	SELECT *, ROW_NUMBER() OVER(PARTITION BY custno ORDER BY custno, goodscode, catecode, p2code) AS rowid --634385,0m16s
	FROM #table_wishlist WHERE custno IN (
		SELECT custno
		FROM #table_wishlist
		GROUP BY custno
		HAVING COUNT(custno) >= 5
	)
) AS t
WHERE rowid <= 5

-- table_5_result (10502808)
-- 15m37s
IF Object_id('tempdb..#table_5_result') IS NOT NULL
	DROP TABLE #table_5_result
CREATE TABLE #table_5_result(
	custno       CHAR(30),
	recomdlist   CHAR(30),
	discounttype INT,
	importance   NVARCHAR(max),
	goodindex    INT
)
INSERT INTO #table_5_result
SELECT DISTINCT x1.custno, x2.recomdlist, x2.discounttype, x2.importance, x1.goodindex
FROM #table_5 AS x1
LEFT JOIN #ardiscount AS x2 ON x1.custno = x2.cust_no AND x1.goodscode = x2.goodscode --800351-46907=753444
WHERE x2.recomdlist IS NOT NULL
UNION
SELECT DISTINCT x1.custno, x2.recomdlist, x2.discounttype, '0', x1.goodindex
FROM #table_5 AS x1
LEFT JOIN #tpdiscount AS x2 ON x1.custno = x2.cust_no AND x1.catecode = x2.catecode --9749743-379=9749364,6m47s
WHERE x2.recomdlist IS NOT NULL

-- verify
--SELECT * FROM #table_5_result --10502808,1m54s
--SELECT DISTINCT * FROM #table_5_result --10502808,3m37s

-- table_5_result2 (1624809)
-- 7m20s
IF Object_id('tempdb..#table_5_result2') IS NOT NULL
	DROP TABLE #table_5_result2
CREATE TABLE #table_5_result2(
	custno       CHAR(30),
	recomdlist   CHAR(30),
	discounttype INT,
	importance   NVARCHAR(max),
	goodindex    INT
)
INSERT INTO #table_5_result2
SELECT custno, recomdlist, discounttype, importance, goodindex --7m52s
FROM(
	SELECT ROW_NUMBER() OVER(PARTITION BY custno+','+CONVERT(nvarchar,goodindex) ORDER BY discounttype, importance DESC, goodindex, custno, recomdlist) AS rowid, *
	FROM(
		SELECT * FROM( --x,xmxxs --10026041,5m37s
			SELECT ROW_NUMBER() OVER(PARTITION BY custno+','+recomdlist+','+CONVERT(nvarchar,goodindex) ORDER BY discounttype, importance DESC) AS rowid3, *
			FROM #table_5_result --10502808,6m12s
		) AS t3
		WHERE rowid3 = 1
	) AS t2
) AS t1
WHERE rowid <= 8
ORDER BY discounttype, importance DESC

-- table_5_result3 (1480153)
-- 0m09s
IF Object_id('tempdb..#table_5_result3') IS NOT NULL
	DROP TABLE #table_5_result3
CREATE TABLE #table_5_result3(
	custno       CHAR(30),
	recomdlist   CHAR(30)
)
INSERT INTO #table_5_result3
SELECT custno, recomdlist --1h55m01s
FROM #table_5_result2
GROUP BY custno, recomdlist
ORDER BY MIN(discounttype), MAX(importance) DESC

-- concat (41112)
-- 0m24s
/*SELECT T1.custno, COUNT(*) AS good_count, (STUFF((
	SELECT ',' + recomdlist
	FROM #table_5_result3 T2
	WHERE T2.custno = T1.custno
	FOR XML PATH('')), 1, 1, ''
)) AS t
FROM #table_5_result3 T1
GROUP BY custno
--HAVING COUNT(*) = 40 --bottleneck!!!
ORDER BY custno*/


--------------------------------------------------------------------------------------------
-- table_final (190703) 2m19s
-- 2m00s
IF Object_id('tempdb..#table_final') IS NOT NULL
	DROP TABLE #table_final
CREATE TABLE #table_final(
	custno       CHAR(30),
	recomdcount  INT,
	recomdlist   NVARCHAR(max)
)
INSERT INTO #table_final
-- concat 89715,0m49s
SELECT T1.custno, COUNT(*) AS good_count, (STUFF((
	SELECT ',' + recomdlist
	FROM #table_1_result2 T2
	WHERE T2.custno = T1.custno
	FOR XML PATH('')), 1, 1, ''
)) AS t
FROM #table_1_result2 T1
GROUP BY custno
UNION
-- concat 32468,0m19s
SELECT T1.custno, COUNT(*) AS good_count, (STUFF((
	SELECT ',' + recomdlist
	FROM #table_2_result3 T2
	WHERE T2.custno = T1.custno
	FOR XML PATH('')), 1, 1, ''
)) AS t
FROM #table_2_result3 T1
GROUP BY custno
UNION
-- concat 16845,0m10s
SELECT T1.custno, COUNT(*) AS good_count, (STUFF((
	SELECT ',' + recomdlist
	FROM #table_3_result3 T2
	WHERE T2.custno = T1.custno
	FOR XML PATH('')), 1, 1, ''
)) AS t
FROM #table_3_result3 T1
GROUP BY custno
UNION
-- concat 10563,0m06s
SELECT T1.custno, COUNT(*) AS good_count, (STUFF((
	SELECT ',' + recomdlist
	FROM #table_4_result3 T2
	WHERE T2.custno = T1.custno
	FOR XML PATH('')), 1, 1, ''
)) AS t
FROM #table_4_result3 T1
GROUP BY custno
UNION
-- concat 41112,0m24s
SELECT T1.custno, COUNT(*) AS good_count, (STUFF((
	SELECT ',' + recomdlist
	FROM #table_5_result3 T2
	WHERE T2.custno = T1.custno
	FOR XML PATH('')), 1, 1, ''
)) AS t
FROM #table_5_result3 T1
GROUP BY custno

-- verify
SELECT recomdcount, COUNT(*) FROM #table_final --190703
GROUP BY recomdcount
ORDER BY recomdcount

SELECT * FROM #table_final
