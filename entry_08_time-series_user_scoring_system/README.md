# Entry 08 - Time-Series User Scoring System

## Overview

One of the challenges in community-driven platforms is measuring user engagement over time rather than evaluating isolated events. A user may be highly active for several months, become inactive for an extended period, and later return to regular participation. Traditional reporting often captures activity counts but does not provide a mechanism for measuring long-term engagement trends.

This project implements a Time-Series User Scoring System using the Stack Overflow public dataset. User activities such as asking questions, posting answers, receiving accepted answers, writing comments, and casting votes are converted into a unified chronological event stream. Each event contributes a weighted score that is accumulated over time to produce a historical participation score.

To discourage score inflation from dormant accounts, the system also introduces inactivity penalties. Every thirty consecutive days without activity results in a score reduction, creating a dynamic balance between contribution and inactivity. The result is a continuously evolving score that reflects both historical participation and recent engagement.

The implementation processes millions of records using PostgreSQL recursive queries, window functions, and incremental score persistence. Rather than recalculating the entire history during each execution, previously calculated scores are used as seed records, allowing the system to continue processing from the last known state.

The final output produces a complete historical timeline showing how a user's score changes over time as new activity occurs and inactivity penalties are applied.


Each user activity is converted into a scoring event and assigned a predefined weight. Positive contributions increase the score, while prolonged inactivity results in periodic penalties. The following table defines the scoring model used by the system.


| Event | Points |
|--------|--------:|
| 🟩 Question Asked | +3 |
| 🟩 Answer Posted But Not Accepted | +5 |
| 🟩 Accepted Answer | +10 |
| 🟩 Comment Posted | +2 |
| 🟩 Vote Cast | +1 |
| 🟥 30 Consecutive Idle Days | -5 |


The sample below demonstrates how the scoring system evolves over time. The row marked with 🔴 red indicators represents a previously calculated seed record loaded from persistent storage. This record is used to resume score calculations from the last known state and is excluded from the final output. It is displayed here only to illustrate how incremental processing continues from previously calculated data. The 🟢 green indicators highlight the `tot` column, which contains the user's cumulative score after all activity and inactivity adjustments have been applied.

### Column Definitions

| Column           | Description                                                                                      |
| ---------------- | ------------------------------------------------------------------------------------------------ |
| `user_id`        | Stack Overflow user identifier.                                                                  |
| `creationdate`   | Date and time the event occurred.                                                                |
| `postid`         | Associated post identifier when applicable.                                                      |
| `action`         | Activity type such as asked, commented, voted, accepted answer, or idle.                         |
| `score`          | Points assigned to the current event based on the scoring rules.                                 |
| `tot`            | Running cumulative score after applying all previous events and inactivity penalties.            |
| `idle_score`     | Daily inactivity indicator used to track idle periods.                                           |
| `tot_idle_score` | Running inactivity counter used to determine when a 30-day penalty should be applied.            |
| `rwn`            | Sequential event number generated using `ROW_NUMBER()` to ensure deterministic processing order. |

Immediately following the seed record, the user reaches thirty consecutive idle days, causing the score to decrease from **745** to **740** and the inactivity counter to reset. On **January 25, 2022**, the user becomes active again by asking a question and posting multiple comments, increasing the score to **761**. Additional comments, votes, and answers continue to raise the score through February and early March, reaching **774** on **February 28, 2022**.

The user then enters another extended inactive period. As the inactivity counter progresses from `-1` to `-29`, a second inactivity penalty is triggered on **March 30, 2022**, reducing the cumulative score from **774** to **769** and resetting the inactivity counter back to zero. Subsequent activity in May once again increases the score, eventually reaching **785**, demonstrating how the system rewards continued participation while gradually reducing the score of dormant accounts through periodic inactivity penalties.


"user_id"|"creationdate"|"postid"|"action"|"score"|🟢"tot"|"idle_score"|"tot_idle_score"|"rwn"
--------|--------:|--------:|--------:|--------:|--------:|--------:|--------:|--------:
🔴8014824|🔴2021-12-31 00:00:00.000|🔴|🔴idle|🔴0|🔴745|🔴-1|🔴-29|🔴0
8014824|2022-01-01 00:00:00.000||idle|0|🟢740|-1|0|1
8014824|2022-01-02 00:00:00.000||idle|0|🟢740|-1|-1|2
8014824|2022-01-03 00:00:00.000||idle|0|🟢740|-1|-2|3
8014824|2022-01-04 00:00:00.000||idle|0|🟢740|-1|-3|4
8014824|2022-01-05 00:00:00.000||idle|0|🟢740|-1|-4|5
8014824|2022-01-06 00:00:00.000||idle|0|🟢740|-1|-5|6
8014824|2022-01-07 00:00:00.000||idle|0|🟢740|-1|-6|7
8014824|2022-01-08 00:00:00.000||idle|0|🟢740|-1|-7|8
8014824|2022-01-09 00:00:00.000||idle|0|🟢740|-1|-8|9
8014824|2022-01-10 00:00:00.000||idle|0|🟢740|-1|-9|10
8014824|2022-01-11 00:00:00.000||idle|0|🟢740|-1|-10|11
8014824|2022-01-12 00:00:00.000||idle|0|🟢740|-1|-11|12
8014824|2022-01-13 00:00:00.000||idle|0|🟢740|-1|-12|13
8014824|2022-01-14 00:00:00.000||idle|0|🟢740|-1|-13|14
8014824|2022-01-15 00:00:00.000||idle|0|🟢740|-1|-14|15
8014824|2022-01-16 00:00:00.000||idle|0|🟢740|-1|-15|16
8014824|2022-01-17 00:00:00.000||idle|0|🟢740|-1|-16|17
8014824|2022-01-18 00:00:00.000||idle|0|🟢740|-1|-17|18
8014824|2022-01-19 00:00:00.000||idle|0|🟢740|-1|-18|19
8014824|2022-01-20 00:00:00.000||idle|0|🟢740|-1|-19|20
8014824|2022-01-21 00:00:00.000||idle|0|🟢740|-1|-20|21
8014824|2022-01-22 00:00:00.000||idle|0|🟢740|-1|-21|22
8014824|2022-01-23 00:00:00.000||idle|0|🟢740|-1|-22|23
8014824|2022-01-24 00:00:00.000||idle|0|🟢740|-1|-23|24
8014824|2022-01-25 20:39:27.530|70855373|asked|3|🟢743|0|0|25
8014824|2022-01-25 21:05:09.870|70709385|commented|2|🟢745|0|0|26
8014824|2022-01-25 21:09:28.080|70764701|commented|2|🟢747|0|0|27
8014824|2022-01-25 21:14:02.083|66700604|commented|2|🟢749|0|0|28
8014824|2022-01-25 21:14:41.870|70772906|commented|2|🟢751|0|0|29
8014824|2022-01-25 21:19:42.260|57894281|commented|2|🟢753|0|0|30
8014824|2022-01-25 21:22:02.827|70777859|commented|2|🟢755|0|0|31
8014824|2022-01-25 21:25:06.313|70806391|commented|2|🟢757|0|0|32
8014824|2022-01-25 21:26:11.807|70816587|commented|2|🟢759|0|0|33
8014824|2022-01-25 21:44:38.397|70836226|commented|2|🟢761|0|0|34
8014824|2022-01-26 00:00:00.000||idle|0|🟢761|-1|-1|35
8014824|2022-01-27 00:00:00.000||idle|0|🟢761|-1|-2|36
8014824|2022-01-28 00:00:00.000||idle|0|🟢761|-1|-3|37
8014824|2022-01-29 00:00:00.000||idle|0|🟢761|-1|-4|38
8014824|2022-01-30 00:00:00.000||idle|0|🟢761|-1|-5|39
8014824|2022-01-31 00:00:00.000||idle|0|🟢761|-1|-6|40
8014824|2022-02-01 00:00:00.000||idle|0|🟢761|-1|-7|41
8014824|2022-02-02 00:00:00.000||idle|0|🟢761|-1|-8|42
8014824|2022-02-03 00:00:00.000||idle|0|🟢761|-1|-9|43
8014824|2022-02-04 00:00:00.000||idle|0|🟢761|-1|-10|44
8014824|2022-02-05 00:00:00.000||idle|0|🟢761|-1|-11|45
8014824|2022-02-06 00:00:00.000||idle|0|🟢761|-1|-12|46
8014824|2022-02-07 22:10:32.213|69320242|commented|2|🟢763|0|0|47
8014824|2022-02-08 00:00:00.000||idle|0|🟢763|-1|-1|48
8014824|2022-02-09 00:00:00.000|60652908|voted|1|🟢764|0|0|49
8014824|2022-02-10 00:00:00.000||idle|0|🟢764|-1|-1|50
8014824|2022-02-11 00:00:00.000||idle|0|🟢764|-1|-2|51
8014824|2022-02-12 00:00:00.000||idle|0|🟢764|-1|-3|52
8014824|2022-02-13 00:00:00.000||idle|0|🟢764|-1|-4|53
8014824|2022-02-14 00:00:00.000||idle|0|🟢764|-1|-5|54
8014824|2022-02-15 00:00:00.000||idle|0|🟢764|-1|-6|55
8014824|2022-02-16 00:00:00.000||idle|0|🟢764|-1|-7|56
8014824|2022-02-17 16:59:21.797|37229338|commented|2|🟢766|0|0|57
8014824|2022-02-17 17:11:59.353|37229338|commented|2|🟢768|0|0|58
8014824|2022-02-18 00:00:00.000||idle|0|🟢768|-1|-1|59
8014824|2022-02-19 00:00:00.000||idle|0|🟢768|-1|-2|60
8014824|2022-02-20 00:00:00.000||idle|0|🟢768|-1|-3|61
8014824|2022-02-21 00:00:00.000||idle|0|🟢768|-1|-4|62
8014824|2022-02-22 00:00:00.000||idle|0|🟢768|-1|-5|63
8014824|2022-02-23 20:21:25.870|71243583|not accepted answer|5|🟢773|0|0|64
8014824|2022-02-24 00:00:00.000||idle|0|🟢773|-1|-1|65
8014824|2022-02-25 00:00:00.000||idle|0|🟢773|-1|-2|66
8014824|2022-02-26 00:00:00.000||idle|0|🟢773|-1|-3|67
8014824|2022-02-27 00:00:00.000||idle|0|🟢773|-1|-4|68
8014824|2022-02-28 00:00:00.000|61316005|voted|1|🟢774|0|0|69
8014824|2022-03-01 00:00:00.000||idle|0|🟢774|-1|-1|70
8014824|2022-03-02 00:00:00.000||idle|0|🟢774|-1|-2|71
8014824|2022-03-03 00:00:00.000||idle|0|🟢774|-1|-3|72
8014824|2022-03-04 00:00:00.000||idle|0|🟢774|-1|-4|73
8014824|2022-03-05 00:00:00.000||idle|0|🟢774|-1|-5|74
8014824|2022-03-06 00:00:00.000||idle|0|🟢774|-1|-6|75
8014824|2022-03-07 00:00:00.000||idle|0|🟢774|-1|-7|76
8014824|2022-03-08 00:00:00.000||idle|0|🟢774|-1|-8|77
8014824|2022-03-09 00:00:00.000||idle|0|🟢774|-1|-9|78
8014824|2022-03-10 00:00:00.000||idle|0|🟢774|-1|-10|79
8014824|2022-03-11 00:00:00.000||idle|0|🟢774|-1|-11|80
8014824|2022-03-12 00:00:00.000||idle|0|🟢774|-1|-12|81
8014824|2022-03-13 00:00:00.000||idle|0|🟢774|-1|-13|82
8014824|2022-03-14 00:00:00.000||idle|0|🟢774|-1|-14|83
8014824|2022-03-15 00:00:00.000||idle|0|🟢774|-1|-15|84
8014824|2022-03-16 00:00:00.000||idle|0|🟢774|-1|-16|85
8014824|2022-03-17 00:00:00.000||idle|0|🟢774|-1|-17|86
8014824|2022-03-18 00:00:00.000||idle|0|🟢774|-1|-18|87
8014824|2022-03-19 00:00:00.000||idle|0|🟢774|-1|-19|88
8014824|2022-03-20 00:00:00.000||idle|0|🟢774|-1|-20|89
8014824|2022-03-21 00:00:00.000||idle|0|🟢774|-1|-21|90
8014824|2022-03-22 00:00:00.000||idle|0|🟢774|-1|-22|91
8014824|2022-03-23 00:00:00.000||idle|0|🟢774|-1|-23|92
8014824|2022-03-24 00:00:00.000||idle|0|🟢774|-1|-24|93
8014824|2022-03-25 00:00:00.000||idle|0|🟢774|-1|-25|94
8014824|2022-03-26 00:00:00.000||idle|0|🟢774|-1|-26|95
8014824|2022-03-27 00:00:00.000||idle|0|🟢774|-1|-27|96
8014824|2022-03-28 00:00:00.000||idle|0|🟢774|-1|-28|97
8014824|2022-03-29 00:00:00.000||idle|0|🟢774|-1|-29|98
8014824|2022-03-30 00:00:00.000||idle|0|🟢769|-1|0|99
8014824|2022-03-31 00:00:00.000||idle|0|🟢769|-1|-1|100
8014824|2022-04-01 00:00:00.000||idle|0|🟢769|-1|-2|101
8014824|2022-04-02 00:00:00.000||idle|0|🟢769|-1|-3|102
8014824|2022-04-03 00:00:00.000||idle|0|🟢769|-1|-4|103
8014824|2022-04-04 00:00:00.000||idle|0|🟢769|-1|-5|104
8014824|2022-04-05 00:00:00.000||idle|0|🟢769|-1|-6|105
8014824|2022-04-06 00:00:00.000||idle|0|🟢769|-1|-7|106
8014824|2022-04-07 00:00:00.000||idle|0|🟢769|-1|-8|107
8014824|2022-04-08 00:00:00.000||idle|0|🟢769|-1|-9|108
8014824|2022-04-09 00:00:00.000||idle|0|🟢769|-1|-10|109
8014824|2022-04-10 00:00:00.000||idle|0|🟢769|-1|-11|110
8014824|2022-04-11 00:00:00.000||idle|0|🟢769|-1|-12|111
8014824|2022-04-12 00:00:00.000||idle|0|🟢769|-1|-13|112
8014824|2022-04-13 00:00:00.000||idle|0|🟢769|-1|-14|113
8014824|2022-04-14 00:00:00.000||idle|0|🟢769|-1|-15|114
8014824|2022-04-15 00:00:00.000||idle|0|🟢769|-1|-16|115
8014824|2022-04-16 00:00:00.000||idle|0|🟢769|-1|-17|116
8014824|2022-04-17 00:00:00.000||idle|0|🟢769|-1|-18|117
8014824|2022-04-18 00:00:00.000||idle|0|🟢769|-1|-19|118
8014824|2022-04-19 00:00:00.000||idle|0|🟢769|-1|-20|119
8014824|2022-04-20 00:00:00.000||idle|0|🟢769|-1|-21|120
8014824|2022-04-21 00:00:00.000||idle|0|🟢769|-1|-22|121
8014824|2022-04-22 00:00:00.000||idle|0|🟢769|-1|-23|122
8014824|2022-04-23 00:00:00.000||idle|0|🟢769|-1|-24|123
8014824|2022-04-24 00:00:00.000||idle|0|🟢769|-1|-25|124
8014824|2022-04-25 00:00:00.000||idle|0|🟢769|-1|-26|125
8014824|2022-04-26 00:00:00.000||idle|0|🟢769|-1|-27|126
8014824|2022-04-27 00:00:00.000||idle|0|🟢769|-1|-28|127
8014824|2022-04-28 00:00:00.000||idle|0|🟢769|-1|-29|128
8014824|2022-04-29 00:00:00.000||idle|0|🟢764|-1|0|129
8014824|2022-04-30 00:00:00.000||idle|0|🟢764|-1|-1|130
8014824|2022-05-01 00:00:00.000||idle|0|🟢764|-1|-2|131
8014824|2022-05-02 00:00:00.000||idle|0|🟢764|-1|-3|132
8014824|2022-05-03 00:00:00.000||idle|0|🟢764|-1|-4|133
8014824|2022-05-04 14:52:41.273|72115079|asked|3|🟢767|0|0|134
8014824|2022-05-05 00:00:00.000||idle|0|🟢767|-1|-1|135
8014824|2022-05-06 00:00:00.000||idle|0|🟢767|-1|-2|136
8014824|2022-05-07 00:00:00.000||idle|0|🟢767|-1|-3|137
8014824|2022-05-08 00:00:00.000||idle|0|🟢767|-1|-4|138
8014824|2022-05-09 00:00:00.000||idle|0|🟢767|-1|-5|139
8014824|2022-05-10 00:00:00.000||idle|0|🟢767|-1|-6|140
8014824|2022-05-11 00:00:00.000||idle|0|🟢767|-1|-7|141
8014824|2022-05-12 00:00:00.000||idle|0|🟢767|-1|-8|142
8014824|2022-05-13 00:00:00.000||idle|0|🟢767|-1|-9|143
8014824|2022-05-14 00:00:00.000||idle|0|🟢767|-1|-10|144
8014824|2022-05-15 00:00:00.000||idle|0|🟢767|-1|-11|145
8014824|2022-05-16 00:00:00.000||idle|0|🟢767|-1|-12|146
8014824|2022-05-17 20:19:08.417|72280192|asked|3|🟢770|0|0|147
8014824|2022-05-17 20:19:08.417|72280193|not accepted answer|5|🟢775|0|0|148
8014824|2022-05-18 00:00:00.000|72115079|voted|1|🟢776|0|0|149
8014824|2022-05-18 07:58:09.127|72285262|not accepted answer|5|🟢781|0|0|150
8014824|2022-05-18 13:05:42.420|72115079|commented|2|🟢783|0|0|151
8014824|2022-05-18 14:47:40.190|72115079|commented|2|🟢785|0|0|152
8014824|2022-05-19 00:00:00.000||idle|0|🟢785|-1|-1|153
8014824|2022-05-20 00:00:00.000||idle|0|🟢785|-1|-2|154
8014824|2022-05-21 00:00:00.000||idle|0|🟢785|-1|-3|155
8014824|2022-05-22 00:00:00.000||idle|0|🟢785|-1|-4|156
8014824|2022-05-23 00:00:00.000||idle|0|🟢785|-1|-5|157
8014824|2022-05-24 00:00:00.000||idle|0|🟢785|-1|-6|158
8014824|2022-05-25 00:00:00.000||idle|0|🟢785|-1|-7|159
8014824|2022-05-26 00:00:00.000||idle|0|🟢785|-1|-8|160
8014824|2022-05-27 00:00:00.000||idle|0|🟢785|-1|-9|161
8014824|2022-05-28 00:00:00.000||idle|0|🟢785|-1|-10|162
8014824|2022-05-29 00:00:00.000||idle|0|🟢785|-1|-11|163
8014824|2022-05-30 00:00:00.000||idle|0|🟢785|-1|-12|164
8014824|2022-05-31 00:00:00.000||idle|0|🟢785|-1|-13|165
8014824|2022-06-01 00:00:00.000||idle|0|🟢785|-1|-14|166
8014824|2022-06-02 00:00:00.000||idle|0|🟢785|-1|-15|167
8014824|2022-06-03 00:00:00.000||idle|0|🟢785|-1|-16|168
8014824|2022-06-04 00:00:00.000||idle|0|🟢785|-1|-17|169
8014824|2022-06-05 00:00:00.000||idle|0|🟢785|-1|-18|170


