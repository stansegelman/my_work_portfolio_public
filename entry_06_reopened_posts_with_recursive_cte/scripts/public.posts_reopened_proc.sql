CREATE OR REPLACE PROCEDURE public.posts_reopened_proc_fmt()
LANGUAGE plpgsql
AS $BODY$
DECLARE
    qry_plan json;
BEGIN
    SET max_parallel_workers_per_gather = 2;
    SET work_mem = '1024MB';
    SET temp_file_limit = '100GB';

    CREATE INDEX IF NOT EXISTS posthistorytypeid_postid_idx
        ON posthistory (posthistorytypeid, postid);

    CREATE INDEX IF NOT EXISTS posts_normalized_parent_idx
        ON posts ((COALESCE(NULLIF(parentid, 0), id)));

    ANALYZE posthistory;
    ANALYZE posts;

    DROP TABLE IF EXISTS reopened_posts;

    FOR qry_plan IN
        EXPLAIN (VERBOSE, FORMAT JSON, BUFFERS, ANALYZE, COSTS, TIMING)
        CREATE TEMP TABLE reopened_posts AS
        SELECT
            COALESCE(NULLIF(p.parentid, 0), p.id) AS parentid,
            ph.creationdate,
            ph.posthistorytypeid,
            ph.postid,
            p.posttypeid,
            p.title,
            p.body,
            p.owneruserid,
            p.tags
        FROM posthistory ph
        INNER JOIN posts p
            ON ph.postid = p.id
        WHERE EXISTS (
            SELECT 1
            FROM posthistory ph2
            INNER JOIN posts p2
                ON ph2.postid = p2.id
            WHERE ph2.posthistorytypeid = 11
              AND COALESCE(NULLIF(p.parentid, 0), p.id)
                  = COALESCE(NULLIF(p2.parentid, 0), p2.id)
        )
    LOOP
        RAISE NOTICE '%', qry_plan;
    END LOOP;

    CREATE INDEX IF NOT EXISTS posthistory_posts_posthistorytypeid_parentid_idx
        ON reopened_posts (posthistorytypeid, parentid);

    ANALYZE reopened_posts;

    COMMIT;

    DROP TABLE IF EXISTS reopened_posts_grp;

    FOR qry_plan IN
        EXPLAIN (VERBOSE, FORMAT JSON, BUFFERS, ANALYZE, COSTS, TIMING)
        CREATE TEMP TABLE reopened_posts_grp AS
        SELECT
            *,
            DENSE_RANK() OVER (
                PARTITION BY a.parentid
                ORDER BY creationdate
            ) AS grp
        FROM reopened_posts a
        WHERE EXISTS (
            SELECT 1
            FROM reopened_posts b
            WHERE a.parentid = b.parentid
              AND b.posthistorytypeid IN (1, 2, 3)
        )
    LOOP
        RAISE NOTICE '%', qry_plan;
    END LOOP;

    CREATE INDEX ON reopened_posts_grp (grp);

    ANALYZE reopened_posts_grp;

    COMMIT;

    DROP TABLE IF EXISTS reopened_final_results;

    FOR qry_plan IN
        EXPLAIN (
            VERBOSE,
            FORMAT JSON,
            BUFFERS,
            ANALYZE,
            COSTS,
            TIMING,
            SUMMARY,
            SETTINGS,
            WAL
        )
        CREATE TABLE public.reopened_final_results AS
        WITH RECURSIVE reopened_posts_grp_cte AS (
            SELECT
                parentid,
                creationdate,
                creationdate AS recordeddate,
                postid,
                posthistorytypeid,
                posttypeid,
                CASE
                    WHEN posthistorytypeid IN (1, 2, 3)
                         AND posttypeid = 1
                    THEN 1
                    ELSE 0
                END AS show_flag,
                title,
                owneruserid,
                body,
                tags,
                grp
            FROM reopened_posts_grp
            WHERE grp = 1

            UNION ALL

            SELECT DISTINCT
                a.parentid,
                a.creationdate,
                CASE
                    WHEN (
                        a.posthistorytypeid IN (1, 2, 3, 10, 11)
                        AND a.posttypeid = 1
                    )
                    OR (
                        date_trunc('day', a.creationdate + interval '12 hours')
                        - date_trunc('day', b.recordeddate + interval '12 hours')
                        >= '90 days'::interval
                    )
                    THEN a.creationdate
                    ELSE b.recordeddate
                END AS recordeddate,
                a.postid,
                a.posthistorytypeid,
                a.posttypeid,
                CASE
                    WHEN (
                        a.posthistorytypeid IN (1, 2, 3, 10, 11)
                        AND a.posttypeid = 1
                    )
                    OR (
                        date_trunc('day', a.creationdate + interval '12 hours')
                        - date_trunc('day', b.recordeddate + interval '12 hours')
                        >= '90 days'::interval
                    )
                    THEN 1
                    ELSE 0
                END AS show_flag,
                a.title,
                a.owneruserid,
                a.body,
                a.tags,
                a.grp
            FROM reopened_posts_grp_cte b
            INNER JOIN reopened_posts_grp a
                ON a.parentid = b.parentid
               AND a.grp = b.grp + 1
        )
        SELECT
            a.parentid,
            a.creationdate,
            a.postid,
            a.title,
            a.owneruserid,
            a.body,
            a.tags,
            a.posthistorytypeid,
            a.posttypeid,
            b.type AS posthistorytype,
            c.type AS posttype
        FROM reopened_posts_grp_cte a
        INNER JOIN posthistorytypes b
            ON a.posthistorytypeid = b.id
        INNER JOIN posttypes c
            ON a.posttypeid = c.id
        WHERE show_flag = 1
        ORDER BY
            parentid,
            grp,
            posttypeid,
            posthistorytypeid
    LOOP
        RAISE NOTICE '%', qry_plan;
    END LOOP;

    ANALYZE reopened_final_results;
END;
$BODY$;