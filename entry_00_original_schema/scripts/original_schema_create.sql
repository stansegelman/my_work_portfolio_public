--
-- PostgreSQL database dump
--

-- Dumped from database version 14.18
-- Dumped by pg_dump version 17.1

-- Started on 2025-06-20 07:39:53

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 8 (class 2615 OID 2200)
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;




--
-- TOC entry 246 (class 1259 OID 8271471)
-- Name: badges_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.badges_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


SET default_table_access_method = heap;

--
-- TOC entry 247 (class 1259 OID 8271472)
-- Name: badges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.badges (
    id integer DEFAULT nextval('public.badges_id_seq'::regclass) NOT NULL,
    userid integer,
    name character varying(50),
    date timestamp without time zone,
    class smallint
);


--
-- TOC entry 248 (class 1259 OID 8271476)
-- Name: comments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.comments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 249 (class 1259 OID 8271477)
-- Name: comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comments (
    id integer DEFAULT nextval('public.comments_id_seq'::regclass) NOT NULL,
    postid integer,
    score integer,
    text character varying(600),
    creationdate timestamp without time zone,
    userdisplayname character varying(40),
    userid integer,
    contentlicense character varying(12)
);


--
-- TOC entry 250 (class 1259 OID 8271483)
-- Name: postlinks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.postlinks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 251 (class 1259 OID 8271484)
-- Name: postlinks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.postlinks (
    id integer DEFAULT nextval('public.postlinks_id_seq'::regclass) NOT NULL,
    creationdate timestamp without time zone,
    postid integer,
    relatedpostid integer,
    linktypeid smallint
);


--
-- TOC entry 252 (class 1259 OID 8271488)
-- Name: posts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.posts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 253 (class 1259 OID 8271489)
-- Name: posts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.posts (
    id integer DEFAULT nextval('public.posts_id_seq'::regclass) NOT NULL,
    posttypeid smallint NOT NULL,
    acceptedanswerid integer,
    parentid integer,
    creationdate timestamp without time zone NOT NULL,
    deletiondate timestamp without time zone,
    score integer,
    viewcount integer,
    body text,
    owneruserid integer DEFAULT 0,
    ownerdisplayname character varying(40),
    lasteditoruserid integer,
    lasteditordisplayname character varying(40),
    lasteditdate timestamp without time zone,
    lastactivitydate timestamp without time zone,
    title character varying(250),
    tags character varying(250),
    answercount integer,
    commentcount integer,
    favoritecount integer,
    closeddate timestamp without time zone,
    communityowneddate timestamp without time zone,
    contentlicense character varying(12)
);


--
-- TOC entry 254 (class 1259 OID 8271496)
-- Name: tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 255 (class 1259 OID 8271497)
-- Name: tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tags (
    id integer DEFAULT nextval('public.tags_id_seq'::regclass) NOT NULL,
    tagname character varying(35) NOT NULL,
    count integer NOT NULL,
    excerptpostid integer,
    wikipostid integer,
    ismoderatoronly bit(1),
    isrequired bit(1)
);


--
-- TOC entry 256 (class 1259 OID 8271501)
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 257 (class 1259 OID 8271502)
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id integer DEFAULT nextval('public.users_id_seq'::regclass) NOT NULL,
    reputation integer,
    creationdate timestamp without time zone,
    displayname character varying(40),
    lastaccessdate timestamp without time zone,
    websiteurl character varying(200),
    location character varying(100),
    aboutme text,
    views integer,
    upvotes integer,
    downvotes integer,
    profileimageurl character varying(200),
    emailhash character varying(32),
    accountid integer
);


--
-- TOC entry 258 (class 1259 OID 8271508)
-- Name: votes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.votes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- TOC entry 259 (class 1259 OID 8271509)
-- Name: votes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.votes (
    id integer DEFAULT nextval('public.votes_id_seq'::regclass) NOT NULL,
    postid integer,
    votetypeid smallint,
    userid integer,
    creationdate timestamp without time zone,
    bountyamount integer
);


--
-- TOC entry 2570 (class 2606 OID 12388586)
-- Name: badges pk_badges__id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.badges
    ADD CONSTRAINT pk_badges__id PRIMARY KEY (id);


--
-- TOC entry 2574 (class 2606 OID 12388588)
-- Name: comments pk_comments__id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT pk_comments__id PRIMARY KEY (id);


--
-- TOC entry 2577 (class 2606 OID 12388590)
-- Name: postlinks pk_postlinks__id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.postlinks
    ADD CONSTRAINT pk_postlinks__id PRIMARY KEY (id);


--
-- TOC entry 2586 (class 2606 OID 12388592)
-- Name: posts pk_posts__id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT pk_posts__id PRIMARY KEY (id);


--
-- TOC entry 2588 (class 2606 OID 12388594)
-- Name: tags pk_tags__id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT pk_tags__id PRIMARY KEY (id);


--
-- TOC entry 2594 (class 2606 OID 12388596)
-- Name: users pk_users__id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT pk_users__id PRIMARY KEY (id);


--
-- TOC entry 2597 (class 2606 OID 12388598)
-- Name: votes pk_votes__id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT pk_votes__id PRIMARY KEY (id);


--
-- TOC entry 2568 (class 1259 OID 12388672)
-- Name: idx_badges_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_badges_userid ON public.badges USING btree (userid);


--
-- TOC entry 2571 (class 1259 OID 12388673)
-- Name: idx_comments_postid_creationdate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_postid_creationdate ON public.comments USING btree (postid, creationdate);


--
-- TOC entry 2572 (class 1259 OID 12388674)
-- Name: idx_comments_userid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_userid ON public.comments USING btree (userid);


--
-- TOC entry 2575 (class 1259 OID 12388675)
-- Name: idx_postlinks_postid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_postlinks_postid ON public.postlinks USING btree (postid);


--
-- TOC entry 2578 (class 1259 OID 12388676)
-- Name: idx_posts_lastactivitydate_del; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_posts_lastactivitydate_del ON public.posts USING btree (lastactivitydate);


--
-- TOC entry 2579 (class 1259 OID 12388677)
-- Name: idx_posts_owneruserid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_posts_owneruserid ON public.posts USING btree (owneruserid);


--
-- TOC entry 2580 (class 1259 OID 12388678)
-- Name: idx_posts_parentid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_posts_parentid ON public.posts USING btree (parentid);


--
-- TOC entry 2581 (class 1259 OID 12388679)
-- Name: idx_posts_posttypeid; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_posts_posttypeid ON public.posts USING btree (posttypeid);


--
-- TOC entry 2582 (class 1259 OID 12388680)
-- Name: idx_posts_score_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_posts_score_tags ON public.posts USING btree (score, tags);


--
-- TOC entry 2583 (class 1259 OID 12388681)
-- Name: idx_posts_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_posts_tags ON public.posts USING btree (tags);


--
-- TOC entry 2584 (class 1259 OID 12388682)
-- Name: idx_posts_title; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_posts_title ON public.posts USING btree (title);


--
-- TOC entry 2589 (class 1259 OID 12388683)
-- Name: idx_users_creationdate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_creationdate ON public.users USING btree (creationdate);


--
-- TOC entry 2590 (class 1259 OID 12388684)
-- Name: idx_users_displayname; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_displayname ON public.users USING btree (displayname);


--
-- TOC entry 2591 (class 1259 OID 12388685)
-- Name: idx_users_location_displayname; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_location_displayname ON public.users USING btree (location, displayname);


--
-- TOC entry 2592 (class 1259 OID 12388686)
-- Name: idx_users_reputation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_reputation ON public.users USING btree (reputation);


--
-- TOC entry 2595 (class 1259 OID 12388687)
-- Name: idx_votes_userid_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_votes_userid_idx ON public.votes USING btree (userid);


--
-- TOC entry 2599 (class 2606 OID 12388883)
-- Name: comments comments_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_userid_fkey FOREIGN KEY (userid) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- TOC entry 2598 (class 2606 OID 12388888)
-- Name: badges fk_bu; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.badges
    ADD CONSTRAINT fk_bu FOREIGN KEY (userid) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- TOC entry 2600 (class 2606 OID 12388893)
-- Name: comments fk_comm1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT fk_comm1 FOREIGN KEY (postid) REFERENCES public.posts(id) ON DELETE RESTRICT DEFERRABLE;


--
-- TOC entry 2601 (class 2606 OID 12388898)
-- Name: postlinks fk_pl1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.postlinks
    ADD CONSTRAINT fk_pl1 FOREIGN KEY (postid) REFERENCES public.posts(id) ON DELETE RESTRICT DEFERRABLE;


--
-- TOC entry 2602 (class 2606 OID 12388903)
-- Name: postlinks fk_pl2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.postlinks
    ADD CONSTRAINT fk_pl2 FOREIGN KEY (relatedpostid) REFERENCES public.posts(id) ON DELETE RESTRICT DEFERRABLE;


--
-- TOC entry 2603 (class 2606 OID 12388908)
-- Name: posts fk_pu; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT fk_pu FOREIGN KEY (owneruserid) REFERENCES public.users(id) ON DELETE RESTRICT DEFERRABLE;


--
-- TOC entry 2604 (class 2606 OID 12388913)
-- Name: tags fk_tp1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT fk_tp1 FOREIGN KEY (excerptpostid) REFERENCES public.posts(id) ON DELETE RESTRICT DEFERRABLE;


--
-- TOC entry 2605 (class 2606 OID 12388918)
-- Name: tags fk_tp2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT fk_tp2 FOREIGN KEY (wikipostid) REFERENCES public.posts(id) ON DELETE RESTRICT DEFERRABLE;


--
-- TOC entry 2606 (class 2606 OID 12388923)
-- Name: votes fk_vp; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT fk_vp FOREIGN KEY (postid) REFERENCES public.posts(id) ON DELETE RESTRICT DEFERRABLE;


--
-- TOC entry 2607 (class 2606 OID 12388928)
-- Name: votes votes_userid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.votes
    ADD CONSTRAINT votes_userid_fkey FOREIGN KEY (userid) REFERENCES public.users(id) ON DELETE RESTRICT;


-- Completed on 2025-06-20 07:40:00

--
-- PostgreSQL database dump complete
--

