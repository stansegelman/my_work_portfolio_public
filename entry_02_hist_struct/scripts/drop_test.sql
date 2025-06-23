create or replace procedure drop_part()
as
$$
declare
comm text;
begin

for comm IN
SELECT format(
  'DROP TABLE IF EXISTS hist.%s_2005to2010;',
  table_base
)
FROM (VALUES
  ('comments_hist'),
  ('votes_hist'),
  ('postlinks_hist'),
  ('tags_hist'),
  ('post_hist')
) AS t(table_base)
LOOP
EXECUTE comm;
END LOOP;
end;
$$
language plpgsql;