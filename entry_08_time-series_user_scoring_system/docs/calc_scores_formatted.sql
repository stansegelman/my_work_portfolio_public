CREATE OR REPLACE PROCEDURE public.calc_scores
(
    IN p_ts1 TIMESTAMP WITHOUT TIME ZONE,
    IN p_ts2 TIMESTAMP WITHOUT TIME ZONE
)
LANGUAGE plpgsql
AS $procedure$
DECLARE
    qry_plan JSON;
BEGIN

    /**************************************************************************
     STEP 1 - PREPARE PREVIOUS SCORE DATA

     Rebuild helper indexes on previous_scores before processing the next
     scoring window.
    **************************************************************************/

    DROP INDEX IF EXISTS previous_scores_userid_creationdate_idx;
    DROP INDEX IF EXISTS previous_scores_creationdate_idx;
    DROP INDEX IF EXISTS previous_scores_sp1_idx;
    DROP INDEX IF EXISTS previous_scores_user_id_rwn_idx;

    CREATE INDEX previous_scores_userid_creationdate_idx
        ON previous_scores(user_id, creationdate);

    CREATE INDEX previous_scores_creationdate_idx
        ON previous_scores(creationdate);

    CREATE INDEX previous_scores_sp1_idx
        ON previous_scores
        (
            user_id,
            (DATE_TRUNC('day', creationdate))
        );

    CREATE INDEX previous_scores_user_id_rwn_idx
        ON previous_scores(user_id, rwn);

    ANALYZE VERBOSE previous_scores;


    /**************************************************************************
     STEP 2 - CAPTURE EACH USER'S PREVIOUS TAIL ROW

     For incremental execution, pull the latest previously calculated score row
     for each user before p_ts1. This becomes the starting point for the next
     recursive score calculation.
    **************************************************************************/

    DROP TABLE IF EXISTS previous_scores_tail;

    FOR qry_plan IN
        EXPLAIN (ANALYZE, VERBOSE, SETTINGS, COSTS, TIMING, BUFFERS, FORMAT JSON)
        CREATE TEMP TABLE previous_scores_tail
        AS
        SELECT
            user_id,
            creationdate,
            postid,
            action,
            score,
            tot,
            idle_score,
            tot_idle_score,
            0 AS rwn
        FROM public.previous_scores
        WHERE (user_id, rwn) IN
        (
            SELECT
                user_id,
                MAX(rwn)
            FROM public.previous_scores
            GROUP BY user_id
        )
          AND creationdate < p_ts1
    LOOP
        RAISE NOTICE '%', qry_plan;

        INSERT INTO saved_qry_plans(qry_type, qry_json)
        VALUES (1, qry_plan);
    END LOOP;

    CREATE INDEX ON previous_scores_tail(user_id);


    /**************************************************************************
     STEP 3 - CREATE COMMON EVENT STAGING TABLE

     All activity types are normalized into the same event shape:
       user_id, creationdate, postid, action, score, idle_score
    **************************************************************************/

    DROP TABLE IF EXISTS posts_score;

    CREATE TEMP TABLE posts_score
    (
        user_id      INT,
        creationdate TIMESTAMP,
        postid       INT,
        action       VARCHAR(20),
        score        INT,
        idle_score   INT
    );


    /**************************************************************************
     STEP 4 - BUILD QUESTION EVENTS

     A question receives +3 points.
    **************************************************************************/

    DROP TABLE IF EXISTS posts_asked;

    FOR qry_plan IN
        EXPLAIN (ANALYZE, VERBOSE, SETTINGS, COSTS, TIMING, BUFFERS, FORMAT JSON)
        CREATE TEMP TABLE posts_asked
        ON COMMIT DROP
        AS
        SELECT
            owneruserid,
            creationdate,
            id AS postid,
            'asked' AS action,
            3 AS score,
            0 AS idle_score
        FROM posts p
        WHERE creationdate >= p_ts1
          AND creationdate <  p_ts2
          AND owneruserid > 0
          AND id > 0
          AND parentid = 0
    LOOP
        RAISE NOTICE '%', qry_plan;

        INSERT INTO saved_qry_plans(qry_type, qry_json)
        VALUES (2, qry_plan);
    END LOOP;

    INSERT INTO posts_score
    SELECT *
    FROM posts_asked;

    COMMIT;


    /**************************************************************************
     STEP 5 - BUILD ACCEPTED ANSWER EVENTS

     An accepted answer receives +10 points. Acceptance is determined from the
     parent question's acceptedanswerid.
    **************************************************************************/

    DROP TABLE IF EXISTS posts_acceptedanswer;

    FOR qry_plan IN
        EXPLAIN (ANALYZE, VERBOSE, SETTINGS, COSTS, TIMING, BUFFERS, FORMAT JSON)
        CREATE TEMP TABLE posts_acceptedanswer
        ON COMMIT DROP
        AS
        SELECT
            p.owneruserid,
            p.creationdate,
            p.id AS postid,
            'accepted answer' AS action,
            10 AS score,
            0 AS idle_score
        FROM posts p
        WHERE p.creationdate >= p_ts1
          AND p.creationdate <  p_ts2
          AND p.id IN
          (
              SELECT p2.acceptedanswerid
              FROM posts p2
              WHERE p2.acceptedanswerid > 0
                AND p2.creationdate >= COALESCE
                (
                    (SELECT MIN(creationdate) FROM previous_scores),
                    p_ts1
                )
          )
          AND p.owneruserid > 0
          AND p.id > 0
          AND p.parentid > 0
    LOOP
        RAISE NOTICE '%', qry_plan;

        INSERT INTO saved_qry_plans(qry_type, qry_json)
        VALUES (3, qry_plan);
    END LOOP;

    INSERT INTO posts_score
    SELECT *
    FROM posts_acceptedanswer;

    COMMIT;


    /**************************************************************************
     STEP 6 - BUILD NON-ACCEPTED ANSWER EVENTS

     A non-accepted answer receives +5 points.
    **************************************************************************/

    DROP TABLE IF EXISTS posts_non_accptedanswer;

    FOR qry_plan IN
        EXPLAIN (ANALYZE, VERBOSE, SETTINGS, COSTS, TIMING, BUFFERS, FORMAT JSON)
        CREATE TEMP TABLE posts_non_accptedanswer
        ON COMMIT DROP
        AS
        SELECT
            p.owneruserid,
            p.creationdate,
            p.id AS postid,
            'not accepted answer' AS action,
            5 AS score,
            0 AS idle_score
        FROM posts p
        WHERE p.creationdate >= p_ts1
          AND p.creationdate <  p_ts2
          AND p.id NOT IN
          (
              SELECT p2.acceptedanswerid
              FROM posts p2
              WHERE p2.acceptedanswerid > 0
                AND p2.creationdate >= COALESCE
                (
                    (SELECT MIN(creationdate) FROM previous_scores),
                    p_ts1
                )
          )
          AND p.owneruserid > 0
          AND p.id > 0
          AND p.parentid > 0
    LOOP
        RAISE NOTICE '%', qry_plan;

        INSERT INTO saved_qry_plans(qry_type, qry_json)
        VALUES (4, qry_plan);
    END LOOP;

    INSERT INTO posts_score
    SELECT *
    FROM posts_non_accptedanswer;

    COMMIT;


    /**************************************************************************
     STEP 7 - BUILD VOTE EVENTS

     A vote receives +1 point.
    **************************************************************************/

    DROP TABLE IF EXISTS posts_voted;

    FOR qry_plan IN
        EXPLAIN (ANALYZE, VERBOSE, SETTINGS, COSTS, TIMING, BUFFERS, FORMAT JSON)
        CREATE TEMP TABLE posts_voted
        ON COMMIT DROP
        AS
        SELECT
            userid,
            creationdate,
            postid,
            'voted' AS action,
            1 AS score,
            0 AS idle_score
        FROM votes v
        WHERE v.creationdate >= p_ts1
          AND v.creationdate <  p_ts2
          AND userid > 0
          AND postid > 0
    LOOP
        RAISE NOTICE '%', qry_plan;

        INSERT INTO saved_qry_plans(qry_type, qry_json)
        VALUES (5, qry_plan);
    END LOOP;

    INSERT INTO posts_score
    SELECT
        userid,
        creationdate,
        postid,
        action,
        score,
        idle_score
    FROM posts_voted;

    COMMIT;


    /**************************************************************************
     STEP 8 - BUILD COMMENT EVENTS

     A comment receives +2 points.
    **************************************************************************/

    DROP TABLE IF EXISTS posts_commented;

    FOR qry_plan IN
        EXPLAIN (ANALYZE, VERBOSE, SETTINGS, COSTS, TIMING, BUFFERS, FORMAT JSON)
        CREATE TEMP TABLE posts_commented
        ON COMMIT DROP
        AS
        SELECT
            userid,
            creationdate,
            postid,
            'commented' AS action,
            2 AS score,
            0 AS idle_score
        FROM comments c
        WHERE c.creationdate >= p_ts1
          AND c.creationdate <  p_ts2
          AND userid > 0
          AND postid > 0
    LOOP
        RAISE NOTICE '%', qry_plan;

        INSERT INTO saved_qry_plans(qry_type, qry_json)
        VALUES (6, qry_plan);
    END LOOP;

    INSERT INTO posts_score
    SELECT
        userid,
        creationdate,
        postid,
        action,
        score,
        idle_score
    FROM posts_commented;

    COMMIT;


    /**************************************************************************
     STEP 9 - INDEX ACTIVITY EVENTS
    **************************************************************************/

    CREATE INDEX idx1
        ON posts_score(creationdate);

    CREATE INDEX idx2
        ON posts_score(user_id);

    CREATE INDEX idx3
        ON posts_score((DATE_TRUNC('day', creationdate)));

    ANALYZE VERBOSE posts_score;

    COMMIT;


    /**************************************************************************
     STEP 10 - BUILD USER LIST

     Include users with activity in the current processing window and users with
     previous score history.
    **************************************************************************/

    DROP TABLE IF EXISTS uniq_users;

    CREATE TEMP TABLE uniq_users
    AS
    SELECT user_id
    FROM posts_score

    UNION

    SELECT user_id
    FROM previous_scores;

    ANALYZE uniq_users;

    COMMIT;


    /**************************************************************************
     STEP 11 - BUILD DAILY USER CALENDAR

     Create one calendar row per user per date in the current activity range.
     This is used to detect days without activity.
    **************************************************************************/

    DROP TABLE IF EXISTS temp_user_dates;

    CREATE TEMP TABLE temp_user_dates
    AS
    WITH RECURSIVE all_dates AS
    (
        SELECT DATE_TRUNC('day', MIN(creationdate)) AS dt
        FROM posts_score

        UNION ALL

        SELECT dt + INTERVAL '1 day'
        FROM all_dates
        WHERE dt + INTERVAL '1 day' <=
        (
            SELECT DATE_TRUNC('day', MAX(creationdate)) AS dt
            FROM posts_score
        )
    )
    SELECT DISTINCT
        dt AS creationdate,
        b.user_id
    FROM all_dates,
         (SELECT user_id FROM uniq_users) b;

    COMMIT;

    RAISE NOTICE '4';

    CREATE INDEX ON temp_user_dates(user_id, creationdate);

    ANALYZE temp_user_dates;
    ANALYZE posts_score;

    COMMIT;


    /**************************************************************************
     STEP 12 - BUILD USER ACTIVITY DAY LOOKUP

     temp_all contains the days on which each user had activity, plus the user's
     first observed activity date. It is used to avoid generating idle rows
     before the user first appears.
    **************************************************************************/

    DROP TABLE IF EXISTS temp_all;

    CREATE TEMP TABLE temp_all
    AS
    SELECT DISTINCT
        user_id,
        DATE_TRUNC('day', creationdate) AS dt,
        MIN(creationdate) OVER (PARTITION BY user_id) AS min_dt
    FROM
    (
        SELECT
            user_id,
            creationdate
        FROM posts_score

        UNION

        SELECT
            user_id,
            creationdate
        FROM previous_scores
    ) x;

    CREATE INDEX ON temp_all(user_id, dt, min_dt);

    ANALYZE VERBOSE temp_all;

    COMMIT;


    /**************************************************************************
     STEP 13 - GENERATE IDLE EVENTS

     An idle day is represented as:
       action     = 'idle'
       score      = 0
       idle_score = -1

     The recursive scoring step later converts every 30 consecutive idle days
     into a -5 score penalty.
    **************************************************************************/

    DROP TABLE IF EXISTS temp_table;

    FOR qry_plan IN
        EXPLAIN (ANALYZE, VERBOSE, SETTINGS, COSTS, TIMING, BUFFERS, FORMAT JSON)
        CREATE TEMP TABLE temp_table
        AS
        SELECT
            a.user_id,
            a.creationdate,
            NULL::INT AS postid,
            'idle' AS action,
            0 AS score,
            -1 AS idle_score
        FROM temp_user_dates a
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM temp_all c
            WHERE c.user_id = a.user_id
              AND c.dt = a.creationdate
        )
          AND EXISTS
        (
            SELECT 1
            FROM temp_all d
            WHERE d.user_id = a.user_id
              AND a.creationdate > d.min_dt
        )
    LOOP
        RAISE NOTICE '%', qry_plan;

        INSERT INTO saved_qry_plans(qry_type, qry_json)
        VALUES (7, qry_plan);
    END LOOP;

    COMMIT;

    DROP INDEX idx1;
    DROP INDEX idx2;
    DROP INDEX idx3;

    RAISE NOTICE '5';

    INSERT INTO posts_score
    SELECT *
    FROM temp_table;

    COMMIT;


    /**************************************************************************
     STEP 14 - REINDEX EVENT STREAM AFTER IDLE ROWS
    **************************************************************************/

    CREATE INDEX idx1
        ON posts_score(creationdate);

    CREATE INDEX idx2
        ON posts_score(user_id);

    CREATE INDEX idx3
        ON posts_score(user_id, creationdate, postid, action);

    ANALYZE VERBOSE posts_score;


    /**************************************************************************
     STEP 15 - SEQUENCE EVENTS PER USER

     The recursive score calculation requires a deterministic event order.
    **************************************************************************/

    DROP TABLE IF EXISTS posts_score_rwn;

    FOR qry_plan IN
        EXPLAIN (ANALYZE, VERBOSE, SETTINGS, COSTS, TIMING, BUFFERS, FORMAT JSON)
        CREATE TEMP TABLE posts_score_rwn
        AS
        SELECT
            *,
            ROW_NUMBER() OVER
            (
                PARTITION BY user_id
                ORDER BY creationdate,
                         postid,
                         action
            ) AS rwn
        FROM posts_score
    LOOP
        RAISE NOTICE '%', qry_plan;

        INSERT INTO saved_qry_plans(qry_type, qry_json)
        VALUES (8, qry_plan);
    END LOOP;

    CREATE INDEX idx4
        ON posts_score_rwn(user_id, rwn);

    CREATE INDEX idx5
        ON posts_score_rwn(user_id);

    CREATE INDEX idx6
        ON posts_score_rwn(rwn);

    ANALYZE VERBOSE posts_score_rwn;

    COMMIT;


    /**************************************************************************
     STEP 16 - CALCULATE SCORES IN USER BATCHES

     Users are processed in batches of 1,000 to keep the recursive CTE smaller
     and more manageable.
    **************************************************************************/

    DECLARE
        arr      INT[];
        mn       INT;
        mx       INT;
        qry_plan JSON;
    BEGIN

        DROP TABLE IF EXISTS t_recr_scores;

        CREATE TEMP TABLE t_recr_scores
        (
            user_id        INT4 NULL,
            creationdate   TIMESTAMP NULL,
            postid         INT4 NULL,
            action         VARCHAR(20) NULL,
            score          INT4 NULL,
            tot            INT4 NULL,
            idle_score     INT4 NULL,
            tot_idle_score INT4 NULL,
            rwn            INT8 NULL
        );

        SELECT ARRAY_AGG(user_id ORDER BY user_id)
        INTO arr
        FROM uniq_users;


        /**********************************************************************
         STEP 16A - PROCESS EACH USER BATCH

         Score rules:
           asked                 +3
           not accepted answer   +5
           accepted answer      +10
           commented             +2
           voted                 +1

         Inactivity rule:
           every 30 consecutive idle days applies -5 to the total score.

         Score floor:
           total score cannot go below zero.
        **********************************************************************/

        FOR mn, mx IN
            SELECT
                g.i,
                LEAST(g.i + 999, ARRAY_LENGTH(arr, 1))
            FROM GENERATE_SERIES(1, ARRAY_LENGTH(arr, 1), 1000) AS g(i)
        LOOP
            RAISE NOTICE '%,%', mn, mx;

            DROP TABLE IF EXISTS temp_results;

            FOR qry_plan IN
                EXPLAIN (ANALYZE, TIMING, COSTS, BUFFERS, VERBOSE, WAL, SETTINGS, FORMAT JSON)
                CREATE TEMP TABLE temp_results
                AS
                WITH RECURSIVE recr_score AS
                (
                    /*
                       Anchor rows:
                         1. Continue from each user's previous score tail row.
                         2. If no previous score exists, start from the first
                            current event for that user.
                    */
                    SELECT *
                    FROM
                    (
                        SELECT
                            user_id,
                            creationdate,
                            postid,
                            action,
                            score,
                            tot,
                            idle_score,
                            tot_idle_score,
                            0::BIGINT AS rwn
                        FROM previous_scores_tail
                        WHERE user_id = ANY(arr[mn:mx])

                        UNION ALL

                        SELECT
                            d.user_id,
                            d.creationdate,
                            d.postid,
                            d.action,
                            d.score,
                            d.score AS tot,
                            d.idle_score,
                            d.idle_score AS tot_idle_score,
                            d.rwn
                        FROM posts_score_rwn d
                        WHERE d.rwn = 1
                          AND d.user_id = ANY(arr[mn:mx])
                          AND NOT EXISTS
                        (
                            SELECT 1
                            FROM previous_scores_tail c
                            WHERE c.user_id = d.user_id
                        )
                    ) AS init

                    UNION ALL

                    /*
                       Recursive rows:
                         Move to the next event for each user and update:
                           - cumulative total score
                           - consecutive idle-day counter
                    */
                    SELECT
                        b.user_id,
                        b.creationdate,
                        b.postid,
                        b.action,
                        b.score,

                        CASE
                            WHEN a.tot_idle_score + b.idle_score = -30
                                THEN GREATEST(a.tot + b.score - 5, 0)
                            ELSE a.tot + b.score
                        END AS tot,

                        b.idle_score,

                        CASE
                            WHEN b.action = 'idle'
                                THEN
                                    CASE
                                        WHEN a.tot_idle_score + b.idle_score = -30
                                            THEN 0
                                        ELSE a.tot_idle_score + b.idle_score
                                    END
                            ELSE 0
                        END AS tot_idle_score,

                        b.rwn
                    FROM recr_score a
                    INNER JOIN posts_score_rwn b
                        ON a.user_id = b.user_id
                       AND a.rwn + 1 = b.rwn
                )
                SELECT *
                FROM recr_score
                WHERE rwn <> 0
            LOOP
                RAISE NOTICE '%', qry_plan;

                INSERT INTO saved_qry_plans(qry_type, qry_json)
                VALUES (9, qry_plan);
            END LOOP;

            ANALYZE VERBOSE posts_score_rwn;
            ANALYZE VERBOSE previous_scores_tail;

            COMMIT;

            RAISE NOTICE '%,%', arr[mn:mx], ARRAY_LENGTH(arr, 1);

            INSERT INTO t_recr_scores
            SELECT *
            FROM temp_results;

            COMMIT;
        END LOOP;


        /**********************************************************************
         STEP 17 - PERSIST NEW SCORE ROWS

         Only insert score rows that do not already exist for the same user and
         day. This supports incremental execution across date ranges.
        **********************************************************************/

        CREATE INDEX ON t_recr_scores(user_id, (DATE_TRUNC('day', creationdate)));

        FOR qry_plan IN
            EXPLAIN (ANALYZE, VERBOSE, FORMAT JSON, COSTS, TIMING, SETTINGS, WAL)
            INSERT INTO previous_scores
            SELECT *
            FROM t_recr_scores a
            WHERE NOT EXISTS
            (
                SELECT 1
                FROM previous_scores b
                WHERE b.user_id = a.user_id
                  AND DATE_TRUNC('day', b.creationdate) = DATE_TRUNC('day', a.creationdate)
            )
        LOOP
            RAISE NOTICE '%', qry_plan;

            INSERT INTO saved_qry_plans(qry_type, qry_json)
            VALUES (10, qry_plan);
        END LOOP;

    END;

END;
$procedure$;
