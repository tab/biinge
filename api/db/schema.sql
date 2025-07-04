--
-- PostgreSQL database dump
--

-- Dumped from database version 16.4
-- Dumped by pg_dump version 16.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: appearance_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.appearance_type AS ENUM (
    'system',
    'light',
    'dark'
);


ALTER TYPE public.appearance_type OWNER TO postgres;

--
-- Name: state_types; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.state_types AS ENUM (
    'want',
    'watching',
    'watched',
    'none'
);


ALTER TYPE public.state_types OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: movies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.movies (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    tmdb_id integer NOT NULL,
    title character varying(255) NOT NULL,
    poster_path character varying(255),
    runtime integer DEFAULT 0 NOT NULL,
    state public.state_types NOT NULL,
    pinned boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.movies OWNER TO postgres;

--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    login character varying(20) NOT NULL,
    email character varying(255) NOT NULL,
    encrypted_password character varying(255) NOT NULL,
    first_name character varying(20) NOT NULL,
    last_name character varying(20) NOT NULL,
    appearance public.appearance_type DEFAULT 'system'::public.appearance_type NOT NULL,
    deleted_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: movies movies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movies
    ADD CONSTRAINT movies_pkey PRIMARY KEY (id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_login_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_login_key UNIQUE (login);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: movies_tmdb_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX movies_tmdb_id_idx ON public.movies USING btree (tmdb_id);


--
-- Name: movies_user_id_state_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX movies_user_id_state_idx ON public.movies USING btree (user_id, state);


--
-- Name: movies_user_id_state_pinned_created_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX movies_user_id_state_pinned_created_idx ON public.movies USING btree (user_id, state, pinned DESC, created_at DESC);


--
-- Name: movies_user_id_tmdb_id_unique; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX movies_user_id_tmdb_id_unique ON public.movies USING btree (user_id, tmdb_id);


--
-- Name: users_created_at_not_deleted_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX users_created_at_not_deleted_idx ON public.users USING btree (created_at DESC) WHERE (deleted_at IS NULL);


--
-- Name: movies movies_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.movies
    ADD CONSTRAINT movies_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

