
CREATE OR REPLACE PROCEDURE public.proc_db_create_matrices(
	)
LANGUAGE 'plpgsql'
AS $BODY$
DECLARE

sql_string1 text;
sql_string2 text;
different_ops text[][];
op text[];
--mn_id bigint;
--mx_id bigint;
BEGIN

--calculate counts for votes and comments for answers for questions created one year from the last date
--where last date is '2022-06-05 06:39:59.28'
DROP TABLE IF EXISTS votes_comments_per_answer_counts;

CREATE TEMP TABLE votes_comments_per_answer_counts AS
WITH params AS (
  SELECT timestamp '2022-06-05 06:39:59.28' AS max_ts
)
SELECT
  p.acceptedanswerid AS answerid,
  COUNT(DISTINCT v.id) AS votes_cnt,
  COUNT(DISTINCT c.id) AS comments_cnt
FROM posts p
CROSS JOIN params
LEFT JOIN votes v ON v.postid = p.acceptedanswerid
LEFT JOIN comments c ON c.postid = p.acceptedanswerid
WHERE p.creationdate BETWEEN params.max_ts - interval '1 year' AND params.max_ts
  AND p.acceptedanswerid > 0
  AND p.posttypeid = 1
GROUP BY p.acceptedanswerid;

--Calculate the votes and comments counts for answers for questions asked a year back from the last day 
--a year back from the last day

--Calculate percentiles for sub_segments

DROP TABLE IF EXISTS sub_segments;
CREATE TEMP TABLE sub_segments
AS
WITH percentiles AS (
SELECT
    percentile_disc(0.00) WITHIN GROUP (ORDER BY votes_cnt) AS p0_votes,
    percentile_disc(0.60) WITHIN GROUP (ORDER BY votes_cnt) AS p60_votes,
    percentile_disc(0.90) WITHIN GROUP (ORDER BY votes_cnt) AS p90_votes,
	percentile_disc(1.00) WITHIN GROUP (ORDER BY votes_cnt) AS p100_votes,
	percentile_disc(0.00) WITHIN GROUP (ORDER BY comments_cnt) AS p0_comments,
	percentile_disc(0.80) WITHIN GROUP (ORDER BY comments_cnt) AS p80_comments,
    percentile_disc(0.93) WITHIN GROUP (ORDER BY comments_cnt) AS p93_comments,
	percentile_disc(1.00) WITHIN GROUP (ORDER BY comments_cnt) AS p100_comments
  FROM votes_comments_per_answer_counts
 )
 	--Calculate sub-segments
SELECT  answerid,
		votes_cnt,
		comments_cnt,
CASE WHEN votes_cnt >=p0_votes AND votes_cnt < p60_votes THEN 'low_vote_tier'
     WHEN votes_cnt >= p60_votes AND votes_cnt <p90_votes THEN 'middle_vote_tier'
	 WHEN votes_cnt >= p90_votes AND votes_cnt <= p100_votes THEN 'high_vote_tier' END votes_sub_seg,
CASE WHEN comments_cnt >= p0_comments AND comments_cnt < p80_comments THEN 'low_engagement'
     WHEN comments_cnt >= p80_comments and comments_cnt < p93_comments THEN 'moderate_engagement'
	 WHEN comments_cnt >= p93_comments AND comments_cnt <= p100_comments THEN 'high_engagement' END comments_sub_seg	 
FROM votes_comments_per_answer_counts,percentiles;

--this table is going to hold the totals of segements to be used for checking.
DROP TABLE IF EXISTS segments_check;
CREATE TEMP TABLE segments_check
AS
SELECT COUNT(CASE WHEN comments_sub_seg = 'high_engagement' THEN answerid END)  seg1,
		COUNT(CASE WHEN comments_sub_seg = 'low_engagement' THEN answerid END)  seg2,
		COUNT(CASE WHEN comments_sub_seg = 'moderate_engagement' THEN answerid END) seg3,
		COUNT(CASE WHEN votes_sub_seg = 'high_vote_tier' THEN answerid END) seg4,
		COUNT(CASE WHEN votes_sub_seg = 'low_vote_tier' THEN answerid END) seg5,
		COUNT(CASE WHEN votes_sub_seg = 'middle_vote_tier' THEN answerid END) seg6,
		COUNT(CASE WHEN comments_sub_seg = 'high_engagement' 
			AND votes_sub_seg = 'high_vote_tier' THEN answerid END) seg7,
		COUNT(CASE WHEN comments_sub_seg = 'low_engagement' 
			AND votes_sub_seg = 'high_vote_tier' THEN answerid END) seg8,
		COUNT(CASE WHEN comments_sub_seg = 'moderate_engagement' 
			AND votes_sub_seg = 'middle_vote_tier' THEN answerid END) seg9,
		COUNT(CASE WHEN comments_sub_seg = 'low_engagement' 
			AND votes_sub_seg = 'middle_vote_tier' THEN answerid END) seg10,
		COUNT(CASE WHEN comments_sub_seg = 'low_engagement' 
			AND votes_sub_seg = 'low_vote_tier' THEN answerid END) seg11,
		COUNT(CASE WHEN comments_sub_seg = 'high_engagement' 
			AND votes_sub_seg = 'low_vote_tier' THEN answerid END)	seg12
FROM sub_segments;

/*
Now this is where we are going to define the real segments to be used.

*/

different_ops = ARRAY[['AND','intersect'],['OR','union'],['AND NOT','minus']];

FOREACH op SLICE 1 IN ARRAY(different_ops)
LOOP

EXECUTE FORMAT('DROP TABLE IF EXISTS all_values_%s;',op[2]);
EXECUTE FORMAT('DROP TABLE IF EXISTS segment_matrix_%s;',op[2]);
with tab
AS
(
SELECT conds,labels
FROM
(VALUES('comments_sub_seg = ''high_engagement''',  'seg1'),
		('comments_sub_seg = ''low_engagement''',  'seg2'),
		('comments_sub_seg = ''moderate_engagement''','seg3'),
		('votes_sub_seg = ''high_vote_tier''', 'seg4'),
		('votes_sub_seg = ''low_vote_tier''', 'seg5'),
		('votes_sub_seg = ''middle_vote_tier''','seg6'),
		('comments_sub_seg = ''high_engagement'' AND votes_sub_seg = ''high_vote_tier''', 'seg7'),
		('comments_sub_seg = ''low_engagement'' AND votes_sub_seg = ''high_vote_tier''','seg8') ,
		('comments_sub_seg = ''moderate_engagement'' AND votes_sub_seg = ''middle_vote_tier''', 'seg9'),
		('comments_sub_seg = ''low_engagement'' AND votes_sub_seg = ''middle_vote_tier''', 'seg10'),
		('comments_sub_seg = ''low_engagement'' AND votes_sub_seg = ''low_vote_tier''', 'seg11'),
		('comments_sub_seg = ''high_engagement'' AND votes_sub_seg = ''low_vote_tier''','seg12')
) val(conds,labels)			
		)
		SELECT 'SELECT '|| STRING_AGG('COUNT(DISTINCT CASE WHEN ('||tab1.conds||') '||op[1]||' ('||tab2.conds||') THEN answerid ELSE NULL END) as '||tab1.labels||'_'||tab2.labels,',')
		|| ' FROM sub_segments;' INTO sql_string1
		FROM tab AS tab1, tab AS tab2;

RAISE NOTICE 'CREATE TEMP TABLE all_values_% AS %',op[2],sql_string1;
RAISE NOTICE E'\n';
RAISE NOTICE E'\n';
EXECUTE (format('CREATE TEMP TABLE all_values_%s AS %s',op[2],sql_string1));

WITH tab
as
(
SELECT val.col
FROM
(VALUES ('seg1'),
		('seg2'),
		('seg3'),
		('seg4'),
		('seg5'),
		('seg6'),
		('seg7'),
		('seg8'),
		('seg9'),
		('seg10'),
		('seg11'),
		('seg12')) as val(col)
)
,qry1
AS
(
SELECT tab1.col as col,string_agg(tab1.col||'_'||tab2.col||' as '||tab2.col ,',' ORDER BY REPLACE(tab2.col,'seg','')::int) counts
FROM tab tab1, tab tab2
GROUP BY tab1.col
ORDER BY REPLACE(tab1.col,'seg','')::int
)
SELECT STRING_AGG('SELECT '''||col||''' as segment,'||counts,' FROM all_values_'||op[2]||' UNION ALL ')||' FROM all_values_'||op[2]  INTO sql_string2
FROM qry1;
RAISE NOTICE 'CREATE TABLE segment_matrix_% as %',op[2],sql_string2;
RAISE NOTICE E'\n';
RAISE NOTICE E'\n';
EXECUTE FORMAT('CREATE TABLE segment_matrix_%s as %s',op[2],sql_string2);

END LOOP;
------------------------------

END;
$BODY$;

