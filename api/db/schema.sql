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
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: appearance_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.appearance_type AS ENUM (
    'system',
    'light',
    'dark'
);


--
-- Name: provider_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.provider_type AS ENUM (
    'jellyfin'
);


--
-- Name: state_types; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.state_types AS ENUM (
    'want',
    'watching',
    'watched',
    'none',
    'playing',
    'played'
);


--
-- Name: status_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.status_type AS ENUM (
    'marked',
    'ignored',
    'unresolved',
    'failed'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: episodes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.episodes (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    season_id uuid NOT NULL,
    tmdb_id integer NOT NULL,
    title character varying(255) NOT NULL,
    poster_path character varying(255) DEFAULT ''::character varying NOT NULL,
    runtime integer DEFAULT 0 NOT NULL,
    state public.state_types NOT NULL,
    air_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    watched_at timestamp with time zone,
    CONSTRAINT episodes_runtime_non_negative CHECK ((runtime >= 0))
);


--
-- Name: games; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.games (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    igdb_id integer NOT NULL,
    title character varying(255) NOT NULL,
    poster_path character varying(255) DEFAULT ''::character varying NOT NULL,
    runtime integer DEFAULT 0 NOT NULL,
    state public.state_types NOT NULL,
    pinned boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    played_at timestamp with time zone,
    synced_at timestamp with time zone,
    released_at timestamp with time zone,
    CONSTRAINT games_runtime_non_negative CHECK ((runtime >= 0))
);


--
-- Name: integrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.integrations (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    provider public.provider_type NOT NULL,
    token_hash character(64) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: movies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.movies (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    tmdb_id integer NOT NULL,
    title character varying(255) NOT NULL,
    poster_path character varying(255) DEFAULT ''::character varying NOT NULL,
    runtime integer DEFAULT 0 NOT NULL,
    state public.state_types NOT NULL,
    pinned boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    watched_at timestamp with time zone,
    synced_at timestamp with time zone,
    released_at timestamp with time zone,
    CONSTRAINT movies_runtime_non_negative CHECK ((runtime >= 0))
);


--
-- Name: seasons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seasons (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    series_id uuid NOT NULL,
    tmdb_id integer NOT NULL,
    title character varying(255) NOT NULL,
    number integer DEFAULT 0 NOT NULL,
    episodes_count integer DEFAULT 0 NOT NULL,
    state public.state_types NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    watched_at timestamp with time zone,
    CONSTRAINT seasons_episodes_count_non_negative CHECK ((episodes_count >= 0)),
    CONSTRAINT seasons_number_non_negative CHECK ((number >= 0))
);


--
-- Name: series; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.series (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    tmdb_id integer NOT NULL,
    title character varying(255) NOT NULL,
    poster_path character varying(255) DEFAULT ''::character varying NOT NULL,
    seasons_count integer DEFAULT 0 NOT NULL,
    episodes_count integer DEFAULT 0 NOT NULL,
    status character varying(255) DEFAULT ''::character varying NOT NULL,
    state public.state_types NOT NULL,
    pinned boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    tracked_state public.state_types,
    synced_at timestamp with time zone,
    last_air_at timestamp with time zone,
    CONSTRAINT series_episodes_count_non_negative CHECK ((episodes_count >= 0)),
    CONSTRAINT series_seasons_count_non_negative CHECK ((seasons_count >= 0))
);


--
-- Name: COLUMN series.state; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.series.state IS 'the show''s effective state, derived from watched seasons when the user has not chosen one';


--
-- Name: COLUMN series.tracked_state; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.series.tracked_state IS 'the state the user explicitly chose; NULL when the row was created by marking an episode';


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    login character varying(20) NOT NULL,
    email character varying(255) NOT NULL,
    encrypted_password character varying(255) NOT NULL,
    first_name character varying(50) NOT NULL,
    last_name character varying(50) NOT NULL,
    appearance public.appearance_type DEFAULT 'system'::public.appearance_type NOT NULL,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: webhooks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.webhooks (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    integration_id uuid NOT NULL,
    payload jsonb NOT NULL,
    status public.status_type NOT NULL,
    error text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: episodes episodes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.episodes
    ADD CONSTRAINT episodes_pkey PRIMARY KEY (id);


--
-- Name: games games_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.games
    ADD CONSTRAINT games_pkey PRIMARY KEY (id);


--
-- Name: integrations integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integrations
    ADD CONSTRAINT integrations_pkey PRIMARY KEY (id);


--
-- Name: movies movies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movies
    ADD CONSTRAINT movies_pkey PRIMARY KEY (id);


--
-- Name: seasons seasons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seasons
    ADD CONSTRAINT seasons_pkey PRIMARY KEY (id);


--
-- Name: series series_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series
    ADD CONSTRAINT series_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: webhooks webhooks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhooks
    ADD CONSTRAINT webhooks_pkey PRIMARY KEY (id);


--
-- Name: episodes_season_id_air_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX episodes_season_id_air_at_idx ON public.episodes USING btree (season_id, air_at DESC);


--
-- Name: episodes_season_id_tmdb_id_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX episodes_season_id_tmdb_id_unique ON public.episodes USING btree (season_id, tmdb_id);


--
-- Name: episodes_watched_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX episodes_watched_at_idx ON public.episodes USING btree (watched_at) WHERE (watched_at IS NOT NULL);


--
-- Name: games_synced_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX games_synced_at_idx ON public.games USING btree (synced_at NULLS FIRST);


--
-- Name: games_user_id_igdb_id_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX games_user_id_igdb_id_unique ON public.games USING btree (user_id, igdb_id);


--
-- Name: games_user_id_played_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX games_user_id_played_at_idx ON public.games USING btree (user_id, played_at) WHERE (played_at IS NOT NULL);


--
-- Name: games_user_id_state_pinned_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX games_user_id_state_pinned_created_idx ON public.games USING btree (user_id, state, pinned DESC, created_at DESC);


--
-- Name: integrations_token_hash_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX integrations_token_hash_unique ON public.integrations USING btree (token_hash);


--
-- Name: integrations_user_id_provider_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX integrations_user_id_provider_unique ON public.integrations USING btree (user_id, provider);


--
-- Name: movies_synced_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX movies_synced_at_idx ON public.movies USING btree (synced_at NULLS FIRST);


--
-- Name: movies_user_id_state_pinned_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX movies_user_id_state_pinned_created_idx ON public.movies USING btree (user_id, state, pinned DESC, created_at DESC);


--
-- Name: movies_user_id_tmdb_id_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX movies_user_id_tmdb_id_unique ON public.movies USING btree (user_id, tmdb_id);


--
-- Name: movies_user_id_watched_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX movies_user_id_watched_at_idx ON public.movies USING btree (user_id, watched_at) WHERE (watched_at IS NOT NULL);


--
-- Name: seasons_series_id_tmdb_id_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX seasons_series_id_tmdb_id_unique ON public.seasons USING btree (series_id, tmdb_id);


--
-- Name: series_synced_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX series_synced_at_idx ON public.series USING btree (synced_at NULLS FIRST);


--
-- Name: series_user_id_state_pinned_created_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX series_user_id_state_pinned_created_idx ON public.series USING btree (user_id, state, pinned DESC, created_at DESC);


--
-- Name: series_user_id_tmdb_id_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX series_user_id_tmdb_id_unique ON public.series USING btree (user_id, tmdb_id);


--
-- Name: users_email_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_email_key ON public.users USING btree (email) WHERE (deleted_at IS NULL);


--
-- Name: users_login_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_login_key ON public.users USING btree (login) WHERE (deleted_at IS NULL);


--
-- Name: webhooks_integration_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX webhooks_integration_id_created_at_idx ON public.webhooks USING btree (integration_id, created_at);


--
-- Name: episodes episodes_season_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.episodes
    ADD CONSTRAINT episodes_season_id_fkey FOREIGN KEY (season_id) REFERENCES public.seasons(id) ON DELETE CASCADE;


--
-- Name: games games_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.games
    ADD CONSTRAINT games_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: integrations integrations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.integrations
    ADD CONSTRAINT integrations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: movies movies_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.movies
    ADD CONSTRAINT movies_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: seasons seasons_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seasons
    ADD CONSTRAINT seasons_series_id_fkey FOREIGN KEY (series_id) REFERENCES public.series(id) ON DELETE CASCADE;


--
-- Name: series series_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series
    ADD CONSTRAINT series_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: webhooks webhooks_integration_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.webhooks
    ADD CONSTRAINT webhooks_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

