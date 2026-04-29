-- DROP PROCEDURE public.mem_spill_analysis_proc();

CREATE OR REPLACE PROCEDURE public.mem_spill_analysis_proc()
 LANGUAGE plpgsql
AS $procedure$

BEGIN
SET WORK_MEM = '64MB';

SET MAX_PARALLEL_WORKERS_PER_GATHER = 1;


drop table if exists  UNIQUE_PARENTS;
CREATE TABLE UNIQUE_PARENTS
AS
SELECT
	DISTINCT COALESCE(nullif(PARENTID,0), ID) AS PARENTID
FROM
	POSTS;

DROP TABLE IF EXISTS parent_groupings;

CREATE TEMP TABLE parent_groupings AS
WITH agg_1 AS
(
    SELECT
        parentid,
        ((ROW_NUMBER() OVER (ORDER BY parentid) - 1) % 300000) + 1 AS rwn1,
        ((ROW_NUMBER() OVER (ORDER BY parentid) - 1) % 30000)  + 1 AS rwn2,
        ((ROW_NUMBER() OVER (ORDER BY parentid) - 1) % 3000)   + 1 AS rwn3,
        ((ROW_NUMBER() OVER (ORDER BY parentid) - 1) % 300)    + 1 AS rwn4,
        ((ROW_NUMBER() OVER (ORDER BY parentid) - 1) % 150)    + 1 AS rwn5
    FROM unique_parents
)
SELECT
    COUNT(parentid) AS parent_count,
    ARRAY_AGG(parentid) AS parentids,
    GROUPING(rwn1) AS g1,
    GROUPING(rwn2) AS g2,
    GROUPING(rwn3) AS g3,
    GROUPING(rwn4) AS g4,
    GROUPING(rwn5) AS g5
FROM agg_1
GROUP BY GROUPING SETS
(
    (rwn1),
    (rwn2),
    (rwn3),
    (rwn4),
    (rwn5)
);



DROP TABLE IF EXISTS PARENT_BATCHES;

CREATE TEMP TABLE PARENT_BATCHES
(
GROUPING VARCHAR(2),
PARENT_COUNT INT,
PARENTS INT[]
);



insert into PARENT_BATCHES
SELECT DISTINCT ON (grouping)
    grouping,
    parent_count,
    parentids AS parents
FROM
(
    SELECT
        CASE
            WHEN (g1, g2, g3, g4, g5) = (0, 1, 1, 1, 1) THEN 'G1'
            WHEN (g1, g2, g3, g4, g5) = (1, 0, 1, 1, 1) THEN 'G2'
            WHEN (g1, g2, g3, g4, g5) = (1, 1, 0, 1, 1) THEN 'G3'
            WHEN (g1, g2, g3, g4, g5) = (1, 1, 1, 0, 1) THEN 'G4'
            WHEN (g1, g2, g3, g4, g5) = (1, 1, 1, 1, 0) THEN 'G5'
        END AS grouping,
        parent_count,
        parentids
    FROM parent_groupings
    WHERE
        (g1, g2, g3, g4, g5) IN
        (
            (0, 1, 1, 1, 1),
            (1, 0, 1, 1, 1),
            (1, 1, 0, 1, 1),
            (1, 1, 1, 0, 1),
            (1, 1, 1, 1, 0)
        )
) x
ORDER BY
    grouping,
    parent_count DESC;

SELECT * FROM PARENT_BATCHES;

drop table if exists temp.exec_plans;
create table temp.exec_plans
(
grouping text,
plan_type varchar(20),
plan json,
creationdate timestamp default clock_timestamp()
);



DECLARE
    v_plan json;
    rec record;
BEGIN
    FOR rec IN
        SELECT grouping, parents
        FROM parent_batches
    LOOP
        FOR v_plan IN
            EXPLAIN (VERBOSE, FORMAT JSON, BUFFERS, COSTS)
            SELECT
                COALESCE(NULLIF(p.parentid, 0), p.id) AS parentid,
                ph.creationdate,
                ph.posthistorytypeid,
                p.posttypeid,
                p.title,
                p.body,
                DENSE_RANK() OVER (
                    PARTITION BY COALESCE(NULLIF(p.parentid, 0), p.id)
                    ORDER BY ph.creationdate
                ) AS rwn
            FROM posthistory ph
            INNER JOIN posts p
                ON ph.postid = p.id
            WHERE COALESCE(NULLIF(p.parentid, 0), p.id) = ANY(rec.parents)
        LOOP
            INSERT INTO temp.exec_plans
            (
                grouping,
                plan_type,
                plan
            )
            VALUES
            (
                rec.grouping,
                'estimated',
                v_plan
            );

            RAISE NOTICE '%', rec.grouping;
        END LOOP;
    END LOOP;
END;







WITH RECURSIVE plan_cte AS
(
    SELECT
        plan_root->'Plan' AS node,
        0 AS level,
        grouping,
        plan_type,
        plan
    FROM temp.exec_plans,
         jsonb_array_elements(plan::jsonb) AS plan_root
    WHERE plan_type = 'estimated'

    UNION ALL

    SELECT
        child_node AS node,
        plan_cte.level + 1 AS level,
        plan_cte.grouping,
        plan_cte.plan_type,
        plan_cte.plan
    FROM plan_cte,
         jsonb_array_elements(COALESCE(plan_cte.node->'Plans', '[]'::jsonb)) AS child_node
)
SELECT
    plan_type,
    grouping,
    level,
    node->>'Node Type' AS node_type,
    (node->>'Plan Rows')::bigint AS plan_rows,
    (node->>'Plan Width')::bigint AS plan_width,
    pg_size_pretty(
        ((node->>'Plan Rows')::bigint * (node->>'Plan Width')::bigint)
    ) AS estimated_sort_bytes,
    '64 MB' AS work_mem,
    node->>'Startup Cost' AS startup_cost,
    node->>'Total Cost' AS total_cost,
    plan
FROM plan_cte
WHERE node->>'Node Type' IN ('Sort', 'Incremental Sort')
ORDER BY
    grouping,
    level;
    
    
DECLARE 
    v_plan json;
    rec record;
BEGIN
    FOR rec IN 
        SELECT grouping, parents 
        FROM parent_batches
    LOOP
        FOR v_plan IN
            EXPLAIN (VERBOSE, FORMAT JSON, BUFFERS, COSTS, ANALYZE, TIMING, WAL)
            SELECT
                COALESCE(NULLIF(p.parentid, 0), p.id) AS parentid,
                ph.creationdate,
                ph.posthistorytypeid,
                p.posttypeid,
                p.title,
                p.body,
                DENSE_RANK() OVER (
                    PARTITION BY COALESCE(NULLIF(p.parentid, 0), p.id)
                    ORDER BY ph.creationdate
                ) AS rwn
            FROM posthistory ph
            INNER JOIN posts p
                ON ph.postid = p.id
            WHERE COALESCE(NULLIF(p.parentid, 0), p.id) = ANY(rec.parents)
        LOOP
            INSERT INTO temp.exec_plans(grouping, plan_type, plan)
            VALUES (rec.grouping, 'actual', v_plan);

            RAISE NOTICE '%', rec.grouping;
        END LOOP;
    END LOOP;
END;


WITH RECURSIVE plan_cte AS
(
    SELECT
        plan_root->'Plan' AS node,
        0 AS level,
        grouping,
        plan_type,
        plan
    FROM temp.exec_plans,
         jsonb_array_elements(plan::jsonb) AS plan_root
    WHERE plan_type = 'actual'

    UNION ALL

    SELECT
        child_node AS node,
        plan_cte.level + 1 AS level,
        plan_cte.grouping,
        plan_cte.plan_type,
        plan_cte.plan
    FROM plan_cte,
         jsonb_array_elements(
             COALESCE(plan_cte.node->'Plans', '[]'::jsonb)
         ) AS child_node
)
SELECT
    plan_type,
    grouping,
    level,
    node->>'Node Type' AS node_type,
    (node->>'Plan Rows')::bigint AS plan_rows,
    (node->>'Plan Width')::bigint AS plan_width,
    pg_size_pretty(
        (node->>'Plan Rows')::bigint *
        (node->>'Plan Width')::bigint
    ) AS est_tot_workmem,
    '64 MB' AS work_mem,
    node->>'Sort Method' AS sort_method,
    node->>'Sort Space Type' AS sort_space_type,
    node->>'Startup Cost' AS startup_cost,
    node->>'Total Cost' AS total_cost
FROM plan_cte
WHERE node->>'Node Type' IN ('Sort', 'Incremental Sort')
ORDER BY level;
end;
$procedure$
;