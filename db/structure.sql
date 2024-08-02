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

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: eth_blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eth_blocks (
    id bigint NOT NULL,
    number bigint NOT NULL,
    block_hash character varying NOT NULL,
    logs_bloom text,
    total_difficulty numeric(78,0),
    receipts_root character varying,
    extra_data character varying,
    withdrawals_root character varying,
    base_fee_per_gas bigint,
    nonce character varying,
    miner character varying,
    excess_blob_gas bigint,
    difficulty bigint,
    gas_limit bigint,
    gas_used bigint,
    parent_beacon_block_root character varying NOT NULL,
    size integer,
    transactions_root character varying,
    state_root character varying,
    mix_hash character varying,
    parent_hash character varying NOT NULL,
    blob_gas_used bigint,
    "timestamp" bigint NOT NULL,
    imported_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_69f1818bcd CHECK (((parent_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_d242b421f4 CHECK (((block_hash)::text ~ '^0x[a-f0-9]{64}$'::text))
);


--
-- Name: eth_blocks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.eth_blocks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: eth_blocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.eth_blocks_id_seq OWNED BY public.eth_blocks.id;


--
-- Name: eth_calls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eth_calls (
    id bigint NOT NULL,
    call_index integer NOT NULL,
    parent_call_index integer,
    block_number bigint NOT NULL,
    block_hash character varying NOT NULL,
    transaction_hash character varying NOT NULL,
    from_address character varying NOT NULL,
    to_address character varying,
    gas bigint,
    gas_used bigint,
    input text,
    output text,
    value numeric(78,0),
    call_type character varying,
    error character varying,
    revert_reason character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_c45d2557d8 CHECK (((block_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_dd2f8d7808 CHECK (((from_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_e24d956c84 CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_f57d9e37cc CHECK (((to_address)::text ~ '^0x[a-f0-9]{40}$'::text))
);


--
-- Name: eth_calls_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.eth_calls_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: eth_calls_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.eth_calls_id_seq OWNED BY public.eth_calls.id;


--
-- Name: eth_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eth_transactions (
    id bigint NOT NULL,
    block_hash character varying NOT NULL,
    block_number bigint NOT NULL,
    tx_hash character varying NOT NULL,
    y_parity integer,
    access_list jsonb,
    transaction_index integer,
    tx_type integer,
    nonce integer,
    input text,
    r character varying,
    s character varying,
    chain_id integer,
    v integer,
    gas bigint,
    max_priority_fee_per_gas numeric(78,0),
    from_address character varying,
    to_address character varying,
    max_fee_per_gas numeric(78,0),
    value numeric(78,0) NOT NULL,
    gas_price numeric(78,0),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_33391faf33 CHECK (((block_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_37ed5d6017 CHECK (((to_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_a4d3f41974 CHECK (((from_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_c0881feb4c CHECK (((tx_hash)::text ~ '^0x[a-f0-9]{64}$'::text))
);


--
-- Name: eth_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.eth_transactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: eth_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.eth_transactions_id_seq OWNED BY public.eth_transactions.id;


--
-- Name: ethscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ethscriptions (
    id bigint NOT NULL,
    transaction_hash character varying NOT NULL,
    block_number bigint NOT NULL,
    block_blockhash character varying NOT NULL,
    transaction_index bigint NOT NULL,
    creator character varying NOT NULL,
    initial_owner character varying NOT NULL,
    block_timestamp bigint NOT NULL,
    content_uri text NOT NULL,
    mimetype character varying NOT NULL,
    processed_at timestamp(6) without time zone,
    processing_state character varying NOT NULL,
    processing_error character varying,
    gas_price bigint,
    gas_used bigint,
    transaction_fee bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_7018b50304 CHECK ((((processing_state)::text = 'pending'::text) OR (processed_at IS NOT NULL))),
    CONSTRAINT chk_rails_788fa87594 CHECK (((block_blockhash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_84591e2730 CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_b577b97822 CHECK (((creator)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_ca0ea47752 CHECK (((processing_state)::text = ANY ((ARRAY['pending'::character varying, 'success'::character varying, 'failure'::character varying])::text[]))),
    CONSTRAINT chk_rails_df21fdbe02 CHECK (((initial_owner)::text ~ '^0x[a-f0-9]{40}$'::text))
);


--
-- Name: ethscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ethscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ethscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ethscriptions_id_seq OWNED BY public.ethscriptions.id;


--
-- Name: facet_blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.facet_blocks (
    id bigint NOT NULL,
    number bigint NOT NULL,
    block_hash character varying NOT NULL,
    eth_block_hash character varying NOT NULL,
    eth_block_number integer NOT NULL,
    base_fee_per_gas bigint NOT NULL,
    extra_data character varying NOT NULL,
    gas_limit bigint NOT NULL,
    gas_used bigint NOT NULL,
    logs_bloom text NOT NULL,
    parent_beacon_block_root character varying,
    parent_hash character varying NOT NULL,
    receipts_root character varying NOT NULL,
    size integer NOT NULL,
    state_root character varying NOT NULL,
    "timestamp" integer NOT NULL,
    transactions_root character varying NOT NULL,
    prev_randao character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_e289f61f63 CHECK (((block_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_fa69e55fa7 CHECK (((parent_hash)::text ~ '^0x[a-f0-9]{64}$'::text))
);


--
-- Name: facet_blocks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.facet_blocks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: facet_blocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.facet_blocks_id_seq OWNED BY public.facet_blocks.id;


--
-- Name: facet_transaction_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.facet_transaction_receipts (
    id bigint NOT NULL,
    transaction_hash character varying NOT NULL,
    block_hash character varying NOT NULL,
    block_number integer NOT NULL,
    contract_address character varying,
    legacy_contract_address_map jsonb DEFAULT '{}'::jsonb NOT NULL,
    cumulative_gas_used bigint NOT NULL,
    deposit_nonce character varying NOT NULL,
    deposit_receipt_version character varying NOT NULL,
    effective_gas_price bigint NOT NULL,
    from_address character varying NOT NULL,
    gas_used bigint NOT NULL,
    logs jsonb DEFAULT '[]'::jsonb NOT NULL,
    logs_bloom text NOT NULL,
    status integer NOT NULL,
    to_address character varying,
    transaction_index integer NOT NULL,
    tx_type character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_038b99632c CHECK (((transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_13f8317911 CHECK (((contract_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_9f12b65d79 CHECK (((block_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_b7acdadd3b CHECK (((from_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_c81a92d38b CHECK (((to_address)::text ~ '^0x[a-f0-9]{40}$'::text))
);


--
-- Name: facet_transaction_receipts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.facet_transaction_receipts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: facet_transaction_receipts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.facet_transaction_receipts_id_seq OWNED BY public.facet_transaction_receipts.id;


--
-- Name: facet_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.facet_transactions (
    id bigint NOT NULL,
    eth_transaction_hash character varying NOT NULL,
    eth_call_index integer NOT NULL,
    block_hash character varying NOT NULL,
    block_number bigint NOT NULL,
    deposit_receipt_version character varying NOT NULL,
    from_address character varying NOT NULL,
    gas bigint NOT NULL,
    gas_limit bigint NOT NULL,
    gas_price numeric(78,0),
    tx_hash character varying NOT NULL,
    input text NOT NULL,
    source_hash character varying NOT NULL,
    to_address character varying,
    transaction_index integer NOT NULL,
    tx_type character varying NOT NULL,
    mint numeric(78,0) NOT NULL,
    value numeric(78,0) NOT NULL,
    max_fee_per_gas numeric(78,0),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_12c02c54dd CHECK (((tx_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_449a99a608 CHECK (((eth_transaction_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_5c5b932304 CHECK (((source_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_5c8a2c3595 CHECK (((block_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_a85c151836 CHECK (((to_address)::text ~ '^0x[a-f0-9]{40}$'::text)),
    CONSTRAINT chk_rails_d9f50b7f8a CHECK (((from_address)::text ~ '^0x[a-f0-9]{40}$'::text))
);


--
-- Name: facet_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.facet_transactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: facet_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.facet_transactions_id_seq OWNED BY public.facet_transactions.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: eth_blocks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_blocks ALTER COLUMN id SET DEFAULT nextval('public.eth_blocks_id_seq'::regclass);


--
-- Name: eth_calls id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_calls ALTER COLUMN id SET DEFAULT nextval('public.eth_calls_id_seq'::regclass);


--
-- Name: eth_transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_transactions ALTER COLUMN id SET DEFAULT nextval('public.eth_transactions_id_seq'::regclass);


--
-- Name: ethscriptions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscriptions ALTER COLUMN id SET DEFAULT nextval('public.ethscriptions_id_seq'::regclass);


--
-- Name: facet_blocks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facet_blocks ALTER COLUMN id SET DEFAULT nextval('public.facet_blocks_id_seq'::regclass);


--
-- Name: facet_transaction_receipts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facet_transaction_receipts ALTER COLUMN id SET DEFAULT nextval('public.facet_transaction_receipts_id_seq'::regclass);


--
-- Name: facet_transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facet_transactions ALTER COLUMN id SET DEFAULT nextval('public.facet_transactions_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: eth_blocks eth_blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_blocks
    ADD CONSTRAINT eth_blocks_pkey PRIMARY KEY (id);


--
-- Name: eth_calls eth_calls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_calls
    ADD CONSTRAINT eth_calls_pkey PRIMARY KEY (id);


--
-- Name: eth_transactions eth_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_transactions
    ADD CONSTRAINT eth_transactions_pkey PRIMARY KEY (id);


--
-- Name: ethscriptions ethscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscriptions
    ADD CONSTRAINT ethscriptions_pkey PRIMARY KEY (id);


--
-- Name: facet_blocks facet_blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facet_blocks
    ADD CONSTRAINT facet_blocks_pkey PRIMARY KEY (id);


--
-- Name: facet_transaction_receipts facet_transaction_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facet_transaction_receipts
    ADD CONSTRAINT facet_transaction_receipts_pkey PRIMARY KEY (id);


--
-- Name: facet_transactions facet_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facet_transactions
    ADD CONSTRAINT facet_transactions_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: idx_on_block_number_transaction_index_c73dc27dfd; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_block_number_transaction_index_c73dc27dfd ON public.facet_transaction_receipts USING btree (block_number, transaction_index);


--
-- Name: idx_on_legacy_contract_address_map_1188d7b51d; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_legacy_contract_address_map_1188d7b51d ON public.facet_transaction_receipts USING gin (legacy_contract_address_map);


--
-- Name: index_eth_blocks_on_block_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_blocks_on_block_hash ON public.eth_blocks USING btree (block_hash);


--
-- Name: index_eth_blocks_on_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_blocks_on_number ON public.eth_blocks USING btree (number);


--
-- Name: index_eth_calls_on_block_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_calls_on_block_hash ON public.eth_calls USING btree (block_hash);


--
-- Name: index_eth_calls_on_block_hash_and_call_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_calls_on_block_hash_and_call_index ON public.eth_calls USING btree (block_hash, call_index);


--
-- Name: index_eth_calls_on_block_hash_and_parent_call_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_calls_on_block_hash_and_parent_call_index ON public.eth_calls USING btree (block_hash, parent_call_index);


--
-- Name: index_eth_calls_on_block_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_calls_on_block_number ON public.eth_calls USING btree (block_number);


--
-- Name: index_eth_calls_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_calls_on_transaction_hash ON public.eth_calls USING btree (transaction_hash);


--
-- Name: index_eth_transactions_on_block_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_transactions_on_block_hash ON public.eth_transactions USING btree (block_hash);


--
-- Name: index_eth_transactions_on_block_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_eth_transactions_on_block_number ON public.eth_transactions USING btree (block_number);


--
-- Name: index_eth_transactions_on_tx_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_eth_transactions_on_tx_hash ON public.eth_transactions USING btree (tx_hash);


--
-- Name: index_ethscriptions_on_block_number_and_transaction_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ethscriptions_on_block_number_and_transaction_index ON public.ethscriptions USING btree (block_number, transaction_index);


--
-- Name: index_ethscriptions_on_processing_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ethscriptions_on_processing_state ON public.ethscriptions USING btree (processing_state);


--
-- Name: index_ethscriptions_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ethscriptions_on_transaction_hash ON public.ethscriptions USING btree (transaction_hash);


--
-- Name: index_facet_blocks_on_block_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_facet_blocks_on_block_hash ON public.facet_blocks USING btree (block_hash);


--
-- Name: index_facet_blocks_on_eth_block_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_facet_blocks_on_eth_block_hash ON public.facet_blocks USING btree (eth_block_hash);


--
-- Name: index_facet_blocks_on_eth_block_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_facet_blocks_on_eth_block_number ON public.facet_blocks USING btree (eth_block_number);


--
-- Name: index_facet_blocks_on_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_facet_blocks_on_number ON public.facet_blocks USING btree (number);


--
-- Name: index_facet_transaction_receipts_on_block_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_facet_transaction_receipts_on_block_hash ON public.facet_transaction_receipts USING btree (block_hash);


--
-- Name: index_facet_transaction_receipts_on_block_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_facet_transaction_receipts_on_block_number ON public.facet_transaction_receipts USING btree (block_number);


--
-- Name: index_facet_transaction_receipts_on_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_facet_transaction_receipts_on_transaction_hash ON public.facet_transaction_receipts USING btree (transaction_hash);


--
-- Name: index_facet_transactions_on_block_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_facet_transactions_on_block_hash ON public.facet_transactions USING btree (block_hash);


--
-- Name: index_facet_transactions_on_block_hash_and_eth_call_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_facet_transactions_on_block_hash_and_eth_call_index ON public.facet_transactions USING btree (block_hash, eth_call_index);


--
-- Name: index_facet_transactions_on_block_number; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_facet_transactions_on_block_number ON public.facet_transactions USING btree (block_number);


--
-- Name: index_facet_transactions_on_eth_transaction_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_facet_transactions_on_eth_transaction_hash ON public.facet_transactions USING btree (eth_transaction_hash);


--
-- Name: index_facet_transactions_on_source_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_facet_transactions_on_source_hash ON public.facet_transactions USING btree (source_hash);


--
-- Name: index_facet_transactions_on_tx_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_facet_transactions_on_tx_hash ON public.facet_transactions USING btree (tx_hash);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20240703161720'),
('20240628125033'),
('20240627143934'),
('20240627143407'),
('20240627143108'),
('20240627142725'),
('20240627142124');

