# Portfolio Entry #3

## Objective

Construct a segment set relationship matrix over a time-scoped population of posts. Segment membership is represented as boolean flags (sub-segments and derived compound segments). The final deliverable is a matrix that quantifies relationships between every pair of segments, including:

Intersection counts: |A ∩ B|

Union counts: |A ∪ B|

Set difference counts: |A \ B|

This matrix provides a high-level “map” of segment overlap, exclusivity, and subset relationships, and serves as a validation artifact for the segmentation rules.

Note: All of the diagrams you see here are generated using Maestro for PostgreSQL, their link https://www.sqlmaestro.com/products/postgresql/maestro/
## Diagrams & Graphs

Orignal
- ![ERD: `public` schema structure](./diagrams/original_schema_overview.jpeg)



## Step 1 — Count votes and comments for accepted answers in the one-year cohort

We count votes and comments for accepted answers to questions that were created within one year of the dataset’s maximum timestamp.  These counts will later be used to define vote-tier and comment-engagement sub-segments.

Cohort definition

Dataset max timestamp: 2022-06-05 06:39:59.28

Include only:

posts.posttypeid = 1 (questions)
posts.acceptedanswerid > 0 (question has an accepted answer)
posts.creationdate BETWEEN max_ts - interval '1 year' AND max_ts

Important:
The time filter applies to the question, not the answer.

The accepted answer is included if it belongs to a qualifying question, even if the answer itself was created outside the one-year window.
Cohort definition (time window on questions).
In the StackOverflow schema, both questions and answers are stored in posts table, votes are coming from the votes table and comments from comments table respectively. Questions are identified by posts.posttypeid = 1, and answered questions record an posts.acceptedanswerid. The dataset’s last available timestamp is 2022-06-05 06:39:59.28. The cohort is defined as answered questions created within the one-year window ending at that timestamp:

Implementation (materialize counts table).
The following query materializes a staging table with one row per accepted answer [votes or comments].postid = acceptedanswerid and two engagement metrics: total votes and total comments. Because both votes and comments are one-to-many relative to an answer, COUNT(DISTINCT ...) is used to prevent multiplicative inflation when joining both fact tables in a single query.
````sql
-- calculate counts for votes and comments for accepted answers
-- for questions created one year from the last date
-- last date is '2022-06-05 06:39:59.28'

DROP TABLE IF EXISTS votes_comments_per_answer_counts;

CREATE TEMP TABLE votes_comments_per_answer_counts AS
WITH params AS (
  SELECT timestamp '2022-06-05 06:39:59.28' AS max_ts
)
SELECT
  p.acceptedanswerid AS postid,
  COUNT(DISTINCT v.id) AS votes_cnt,
  COUNT(DISTINCT c.id) AS comments_cnt
FROM posts p
CROSS JOIN params
LEFT JOIN votes v
  ON v.postid = p.acceptedanswerid
LEFT JOIN comments c
  ON c.postid = p.acceptedanswerid
WHERE p.creationdate BETWEEN params.max_ts - interval '1 year' AND params.max_ts
  AND p.acceptedanswerid > 0
  AND p.posttypeid = 1
GROUP BY p.acceptedanswerid;
````

Output.
Step 1 produces votes_comments_per_answer_counts(postid, votes_cnt, comments_cnt), which Step 2 consumes to derive vote tiers and comment engagement tiers (the first-layer sub-segments).
- ![Sample Output](./diagrams/output1.jpg)

## Step 2 — Derive percentile-based sub-segments (vote tier + comment engagement)

With the base engagement counts available (votes_comments_per_answer_counts), the next step is to classify each accepted answer (answerid) into sub-segments. These sub-segments are the primitive building blocks used later to construct boolean segment membership and generate the segment relationship matrix.

Approach.
Sub-segment boundaries are derived from the empirical distribution of the cohort using percentile_disc. For transparency, the 0th and 100th percentiles are included alongside the internal cut points to make the full range explicit.

Vote tiers are defined using the 60th and 90th percentiles:

low_vote_tier: [p0, p60)

middle_vote_tier: [p60, p90)

high_vote_tier: [p90, p100]

Comment engagement tiers are defined using the 80th and 93rd percentiles:

low_engagement: [p0, p80)

moderate_engagement: [p80, p93)

high_engagement: [p93, p100]

Each answerid receives both a vote-tier label and a comment-engagement label, producing a compact categorical representation for downstream segment logic.

Implementation (materialize sub-segments table).
````sql
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
     WHEN votes_cnt >= p60_votes AND votes_cnt < p90_votes THEN 'middle_vote_tier'
	 WHEN votes_cnt >= p90_votes AND votes_cnt <= p100_votes THEN 'high_vote_tier' END votes_sub_seg,
CASE WHEN comments_cnt >= p0_comments AND comments_cnt < p80_comments THEN 'low_engagement'
     WHEN comments_cnt >= p80_comments and comments_cnt < p93_comments THEN 'moderate_engagement'
	 WHEN comments_cnt >= p93_comments AND comments_cnt <= p100_comments THEN 'high_engagement' END comments_sub_seg	 
FROM votes_comments_per_answer_counts CROSS JOIN percentiles;
````
To make the tier boundaries explicit, the query below emits the percentile cut points used for classification. In the sample run shown here, the minimum values for both metrics were 0, but p0_* should be interpreted as the minimum observed count (not inherently “zero”).
- ![Sample Output](./diagrams/output3.jpg)

Output.
This step produces sub_segments(postid, votes_cnt, comments_cnt, votes_sub_seg, comments_sub_seg). These categorical sub-segments are used in the next section to define compound segments and produce boolean membership vectors suitable for matrix-based set operations.
- ![Sample Output](./diagrams/output2.jpg)
