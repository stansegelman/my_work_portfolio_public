CREATE OR REPLACE PROCEDURE public.delete_era_test()
AS $$
DECLARE
    log_stmnt text;
    plan json;
	rec record;
    log_stmnts text[] := ARRAY[
        $sql$
        DELETE FROM public.comments
        WHERE postid IN (
            SELECT id FROM public.posts
            WHERE lastactivitydate >= '2005-01-01'
              AND lastactivitydate <  '2010-01-01'
        )
        $sql$,

        $sql$
        DELETE FROM public.votes
        WHERE postid IN (
            SELECT id FROM public.posts
            WHERE lastactivitydate >= '2005-01-01'
              AND lastactivitydate <  '2010-01-01'
        )
        $sql$,

        $sql$
        DELETE FROM public.postlinks
        WHERE postid IN (
            SELECT id FROM public.posts
            WHERE lastactivitydate >= '2005-01-01'
              AND lastactivitydate <  '2010-01-01'
        )
        $sql$,

        $sql$
        DELETE FROM public.postlinks
        WHERE relatedpostid IN (
            SELECT id FROM public.posts
            WHERE lastactivitydate >= '2005-01-01'
              AND lastactivitydate <  '2010-01-01'
        )
        $sql$,

        $sql$
        DELETE FROM public.tags
        WHERE wikipostid IN (
            SELECT id FROM public.posts
            WHERE lastactivitydate >= '2005-01-01'
              AND lastactivitydate <  '2010-01-01'
        )
        $sql$,

        $sql$
        DELETE FROM public.tags
        WHERE excerptpostid IN (
            SELECT id FROM public.posts
            WHERE lastactivitydate >= '2005-01-01'
              AND lastactivitydate <  '2010-01-01'
        )
        $sql$,

        $sql$
        DELETE FROM public.posts
        WHERE lastactivitydate >= '2005-01-01'
          AND lastactivitydate <  '2010-01-01'
        $sql$
    ];
BEGIN
	RAISE NOTICE 'start time: %!',clock_timestamp();

	truncate temp.test_execution_log;
	drop table if exists so_foreign_keys;
	create temp table so_foreign_keys
	as
	SELECT
	    format('ALTER TABLE %I.%I DROP CONSTRAINT %I;',n.nspname
			,c.relname,con.conname
				,pg_get_constraintdef(con.oid, true) ) drp_stmnt,
	    format('ALTER TABLE %I.%I ADD CONSTRAINT %I %s;',n.nspname
			,c.relname,con.conname
				,pg_get_constraintdef(con.oid, true) ) crt_stmnt,
		n.nspname AS schema_name,
	    c.relname AS table_name,
	    con.conname AS constraint_name,
	    con.contype AS constraint_type,
	    pg_get_constraintdef(con.oid, true) AS definition,
		a.attname
	FROM pg_constraint con
	JOIN pg_class c ON c.oid = con.conrelid
	JOIN pg_namespace n ON n.oid = c.relnamespace
	JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY(con.conkey)
	WHERE n.nspname = 'public'
	  AND con.contype = 'f'
	  AND pg_get_constraintdef(con.oid, true)  ~* 'REFERENCES.*posts\(' ;

	for rec IN
	SELECT * FROM so_foreign_keys
	LOOP
	RAISE NOTICE '%',rec.drp_stmnt;
	EXECUTE rec.drp_stmnt;
	END LOOP;
  
	
    FOREACH log_stmnt IN ARRAY log_stmnts
    LOOP
        EXECUTE format('EXPLAIN (ANALYZE,VERBOSE,COSTS,TIMING,SUMMARY,WAL,BUFFERS,FORMAT JSON) %s', log_stmnt)
        INTO plan;

        RAISE NOTICE 'Logged statement: %', log_stmnt;
       

	END LOOP;

	for rec IN
	SELECT * FROM so_foreign_keys
	LOOP
	RAISE NOTICE '%',rec.crt_stmnt;
	EXECUTE rec.crt_stmnt;
	END LOOP;
	
	ROLLBACK;  --testing
	RAISE NOTICE 'end time: %!',clock_timestamp();
END;
$$
LANGUAGE 'plpgsql';