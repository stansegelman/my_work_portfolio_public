CREATE OR REPLACE FUNCTION fn_era_counts()
RETURNS TABLE (era TEXT, cnt BIGINT)
LANGUAGE plpgsql
AS $$
DECLARE
  str TEXT;
  query TEXT := '';
BEGIN
  SET timezone = 'UTC';

  FOR str IN
    SELECT E'SELECT CASE\n'
    UNION ALL
    SELECT format(
      E'  WHEN lastactivitydate >= %L::timestamp AND lastactivitydate < %L::timestamp + interval ''5 years'' THEN ''%s''\n',
      g.dt, g.dt,
      to_char(g.dt, 'YYYY') || '–' || to_char(g.dt + interval '5 years', 'YYYY')
    )
    FROM generate_series('2005-01-01'::date, '2020-01-01'::date, interval '5 years') AS g(dt)
    UNION ALL
    SELECT
      E'  ELSE ''Other''\nEND AS era,\n  COUNT(*) AS cnt\nFROM public.posts\nWHERE lastactivitydate IS NOT NULL\nGROUP BY 1\nORDER BY 1;'
  LOOP
    query := query || str;
  END LOOP;

  RETURN QUERY EXECUTE query;
END;
$$;