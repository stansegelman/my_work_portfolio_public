
# PostgreSQL Deletion Engine – Complete Technical Portfolio Entry


## 1. Project Introduction


Modern relational databases often contain complex, deeply interlinked schemas that make safe and complete deletion of user-related data extremely challenging. Relying on ON DELETE CASCADE is risky, and disabling constraints can result in data integrity issues. This project presents a high-performance, recursive deletion engine built entirely in PostgreSQL that solves this problem without modifying the schema. The system recursively traverses foreign key chains, generates constraint-respecting DELETE statements using nested EXISTS clauses, and executes them in the correct order of dependency. All deletions are scoped to a userId and tested in dry-run mode using ROLLBACK to ensure safety before commit.  It also sometimes will include a condition if userid or owneruserid is found it will be set to the value.
Note: All of the diagrams you see here are generated using Maestro for PostgreSQL, their link https://www.sqlmaestro.com/products/postgresql/maestro/

## 2. Database Architecture


![ER Diagram](../diagrams/original_schema_overview.jpeg)
The deletion engine is built around a Stack Overflow–style relational schema with well-defined foreign key relationships. The core tables and their interactions can be summarized as follows:


* `users`: The central table containing the primary user identity (`id`).
* `posts`: Questions and answers authored by users.
* `comments`: Associated with users and posts.
* `votes`: Upvotes and downvotes on posts.
* `badges`: Awards linked to `userid`.
* `post_links`: Relational links between posts.
* `post_history`: Revision logs of posts.
* `tags`, `taggings`, `post_tags`: Metadata linkage.


## 3. Problem Solving and Technical Strategy


This engine is designed to safely delete all user-associated data from a relational PostgreSQL schema without using ON DELETE CASCADE or disabling constraints...


## 4. Full Deletion Engine Procedure



```

--Procedure: public.proc_remove_user(bigint)

--DROP PROCEDURE public.proc_remove_user(bigint);

CREATE OR REPLACE PROCEDURE public.proc_remove_user
(
  IN  in_user_id  bigint
)
AS $$
DECLARE

rowcount bigint;

rec RECORD;

BEGIN

drop table if exists relevant_fks;

create temp table relevant_fks
as
WITH referenced_tables AS (
    SELECT 
        c.conrelid AS referencing_table_id,
        c.confrelid AS referenced_table_id
    FROM pg_constraint c
    WHERE c.contype = 'f'
),
only_referenced AS (
    SELECT rt.referenced_table_id
    FROM referenced_tables rt
    LEFT JOIN referenced_tables rt2 
        ON rt.referenced_table_id = rt2.referencing_table_id
    WHERE rt2.referencing_table_id IS NULL
),
leaf_tables AS (
    SELECT 
        c.oid AS table_id,
        n.nspname AS schema_name,
        c.relname AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE c.oid IN (SELECT referenced_table_id FROM only_referenced)
),

-- FK mapping with constraint-specific grouping
fk_mapped AS (
    SELECT 
        c.oid AS constraint_id,
        c.conname AS constraint_name,

        np.nspname AS referenced_schema,
        format('%I',p.relname) AS referenced_table,
        string_agg(format('%I.%I',p.relname,pa.attname)::text, ',' ORDER BY ref_cols.ord) AS referenced_columns,

        n.nspname AS referencing_schema,
        format('%I',r.relname) AS referencing_table,
        string_agg(format('%I.%I',r.relname,ra.attname)::text, ',' ORDER BY fk_cols.ord) AS referencing_columns

    FROM pg_constraint AS c
    JOIN pg_class r ON c.conrelid = r.oid    
    JOIN pg_namespace n ON r.relnamespace = n.oid 
    JOIN pg_class p ON c.confrelid = p.oid
    JOIN pg_namespace np ON p.relnamespace = np.oid

    -- Unnest referencing columns with ordinal alignment
    JOIN unnest(c.conkey) WITH ORDINALITY AS fk_cols(attnum, ord) ON TRUE
    JOIN pg_attribute ra ON ra.attrelid = r.oid AND ra.attnum = fk_cols.attnum

    -- Unnest referenced columns with ordinal match
    JOIN unnest(c.confkey) WITH ORDINALITY AS ref_cols(attnum, ord) ON fk_cols.ord = ref_cols.ord
    JOIN pg_attribute pa ON pa.attrelid = p.oid AND pa.attnum = ref_cols.attnum

    WHERE 
        c.contype = 'f'
        AND n.nspname = 'public'
        AND np.nspname = 'public'

    GROUP BY 
        c.oid, c.conname,
        np.nspname, p.relname,
        n.nspname, r.relname
)

-- Final output
SELECT 
    constraint_id,
    constraint_name,
    referenced_schema,
    referenced_table,
    referenced_columns,
    referencing_schema,
    referencing_table,
    referencing_columns
FROM fk_mapped
UNION
-- Append leaf tables as "structure-only" entries
SELECT 
    NULL AS constraint_id,
    NULL AS constraint_name,
    NULL AS referenced_schema,
    NULL AS referenced_table,
    NULL AS referenced_columns,
    lt.schema_name AS referencing_schema,
    lt.table_name AS referencing_table,
    NULL AS referencing_columns
FROM leaf_tables lt
ORDER BY referencing_schema, referencing_table, constraint_name;

drop table if exists relevant_fks2;

CREATE TEMP TABLE relevant_fks2
AS
with recursive recr_columns
as
(
----this is initial set to b used in the recursion
 SELECT DISTINCT 
		a.referencing_schema,
		a.referencing_table,
		a.referencing_columns,
		a.referenced_schema,
		a.referenced_table,
		a.referenced_columns,
		CASE WHEN c.referenced_columns ~ '^(owner)?userid$' or (a.referencing_table = 'users' and a.referencing_schema = 'public' )
			THEN 1 ELSE 0 END uidflag ,  --ok this column is userid flag , this will flag us while going through all the tables some userid column was found here
		1 lvl, --level of the recursions tree starting with 1
		format('DELETE FROM %I.%I 
					 WHERE %s;',
					a.referencing_schema,
					a.referencing_table,
					CASE 
						WHEN a.referencing_schema = 'public' AND a.referencing_table IN ('votes','comments') THEN ''
						WHEN c.referenced_columns ~ '^(owner)?userid$' 
							THEN format(regexp_replace(c.referenced_columns,'.*?,?((owner)?userid),?.*',' \1 = %s '),in_user_id) --if there is a key that contains some userid value we will parse it out and make it equal to the id we want to remove
						WHEN  a.referencing_table = 'users' and a.referencing_schema = 'public'  --this is the special situation when we are dealing with the users table in that case we know that the column is id not some userid
							THEN format(' users.id = %s ',in_user_id )
						WHEN d.column_name is not null
							THEN format(' %I.%I = %s',a.referencing_table,d.column_name,in_user_id)  -- in this case there is some column not in the users table and it is not referenced by keys but simply by its name is suggests that is some userid
					END
		) COLLATE "C" del_stmnt ,
		'SELECT 1' COLLATE "C" AS sel_stmnt			--default																
	FROM relevant_fks a inner join lateral (
												select b.referenced_columns
												from relevant_fks b
												where b.referenced_schema = a.referencing_schema
												and b.referenced_table = a.referencing_table
											) c on true  --ok c, we need to find out what column in our initial tables are being referenced by other tables
														 --if the foreign keys exists, in this case it gets --users.id
						left join lateral (
												select b.column_name
												from information_schema.columns b
												where b.table_schema = a.referencing_schema
												and b.table_name = a.referencing_table
												and b.column_name ~ '^(owner)?userid$'
												limit 1
											) d on true		--in this case there does not exist foreign index on our column but the column name is 
															 --is suggesting it is a user id
    WHERE a.referencing_table IS NOT NULL AND a.referenced_table IS NULL -- this filter identifies only tables that are being referenced
																		  --that means the referencing table exists but the referenced table does not		

	UNION ALL
    
	SELECT 
		b.referencing_schema,
		b.referencing_table,
		b.referencing_columns, 
		a.referencing_schema,
		a.referencing_table,
		a.referencing_columns,
		
		-- clidflag
		CASE WHEN b.referencing_columns ~ '^(owner)?userid$' OR 
		(b.referencing_schema = 'public' AND b.referencing_table = 'users') OR d.column_name is not null THEN 1 ELSE uidflag END --ok if our userid column exists then mark it it will be important at the end
		,
		
		lvl+1, --increasing the level
		
		-- stmnt
		 
		format('DELETE FROM %I.%I 
					 WHERE %s EXISTS (%s);',
					a.referencing_schema,
					a.referencing_table,
					CASE 
						WHEN a.referencing_schema = 'public' AND a.referencing_table IN ('votes','comments') THEN ''
						WHEN a.referencing_columns ~ '^(owner)?userid$'
							THEN format(regexp_replace(a.referencing_columns,'.*?,?((owner)?userid),?.*',' \1 = %s AND '),in_user_id)
						WHEN a.referencing_schema = 'public' AND a.referencing_table = 'users'
							THEN format('users.id = %s AND ',in_user_id)
						WHEN d.column_name is not null
							THEN format(' %I.%I = %s AND ',a.referencing_table,d.column_name,in_user_id)
						ELSE '' 
					END,
					a.sel_stmnt) del_stmnt,  --this is the final delete statement that is construncted, this is what will finally be executed,
												--also notice it will also consist of select statements calculated in the next column
		
		format ('SELECT 1 
					FROM %I.%I 
					WHERE (%s) = (%s) %s
					AND EXISTS (%s)'
						,a.referencing_schema,a.referencing_table,b.referenced_columns,b.referencing_columns
						,CASE 	
							WHEN a.referencing_schema = 'public' AND a.referencing_table IN ('votes','comments') THEN ''
							WHEN b.referencing_columns ~* '^(owner)?userid$'
									THEN format(regexp_replace(b.referencing_columns,'.*?,?([^.,]+\."?((owner)?userid)"?),?.*?','AND \1 = %s '),in_user_id)
							
							WHEN a.referencing_schema = 'public' AND a.referencing_table = 'users'
									THEN format('AND users.id = %s',in_user_id)
							WHEN d.column_name is not null
							THEN format('AND %I.%I = %s',a.referencing_table,d.column_name,in_user_id)
						ELSE '' END, sel_stmnt) sel_stmnt  --this is what creates specific select statements , it is generated in such a way that it will conform to the foriegn key relationships
	 	
		
    FROM recr_columns a 
	LEFT JOIN  relevant_fks b ON a.referencing_schema = b.referenced_schema --we will start generating all other tables that are referencing public.users and other tables that are referencing those tables
		AND a.referencing_table = b.referenced_table
	left join lateral (
												select b.column_name
												from information_schema.columns b
												where b.table_schema = a.referencing_schema
												and b.table_name = a.referencing_table
												and b.column_name ~ '^(owner)?userid$'
												limit 1
											) d on true		--this is where we simply going to look while the table we are processing does some kind of userid column exist
	WHERE a.referencing_schema IS NOT NULL   	--this will retrieve public.users from the top on first iteration	

	)
SELECT DISTINCT ON (lvl,del_stmnt) * 
FROM recr_columns
WHERE uidflag = 1 and lvl<>2
ORDER BY lvl DESC,del_stmnt;

--RETURN; --testing

FOR rec IN
	SELECT * FROM relevant_fks2
	ORDER BY lvl desc --start from the last
LOOP

RAISE NOTICE '%', rec.del_stmnt;

EXECUTE rec.del_stmnt;

GET DIAGNOSTICS rowcount = ROW_COUNT;

RAISE NOTICE 'ROWS DELETED %.',rowcount;

END LOOP;

ROLLBACK; --TESTING

END;
$$
LANGUAGE 'plpgsql';



```

## 5. Example of Generated SQL Output with Graph

![Flow Diagram](../diagrams/relationship_delete.jpeg)

```

DELETE FROM public.comments
WHERE EXISTS (
    SELECT 1
    FROM public.posts
    WHERE (posts.id) = (comments.postid) AND posts.owneruserid = 9
    AND EXISTS (
        SELECT 1
        FROM public.users
        WHERE (users.id) = (posts.owneruserid) AND posts.owneruserid = 9
        AND EXISTS (SELECT 1)
    )
);
-- NOTICE: ROWS DELETED 74
  
```


## 6. Database Volume and Index Overview


![Table Sizes ](../diagrams/relation_sizes.jpg)

![Row Counts ](../diagrams/relation_counts.jpg)

## 7. Query Execution time 47.800 seconds 

## 8. Execution Environment and System Metrics

* OS: Windows 11 Pro (Build 26100)
* CPU: Intel Core i7 (13th Gen, 12 cores / 16 threads)
* RAM: 32 GB DDR4 @ 4800 MT/s
* Disk: Samsung NVMe SSD (954 GB)
* PostgreSQL 14.18 on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0, 64-bit
* Total DB Size: 205 GB
* CPU Load: ~23% peak during execution
* RAM Usage: ~13 GB steady
* Disk I/O: Minimal due to efficient indexing and memory planning


