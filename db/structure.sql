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
-- Name: check_eth_block_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_eth_block_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
        BEGIN
          IF (SELECT MAX(number) FROM eth_blocks) IS NOT NULL AND (NEW.number <> (SELECT MAX(number) + 1 FROM eth_blocks) OR NEW.parent_hash <> (SELECT block_hash FROM eth_blocks WHERE number = NEW.number - 1)) THEN
            RAISE EXCEPTION 'New block number must be equal to max block number + 1, or this must be the first block. Provided: new number = %, expected number = %, new parent hash = %, expected parent hash = %',
            NEW.number, (SELECT MAX(number) + 1 FROM eth_blocks), NEW.parent_hash, (SELECT block_hash FROM eth_blocks WHERE number = NEW.number - 1);
          END IF;
          RETURN NEW;
        END;
        $$;


--
-- Name: check_ethscription_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_ethscription_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
        BEGIN
          IF NEW.block_number < (SELECT MAX(block_number) FROM ethscriptions) OR (NEW.block_number = (SELECT MAX(block_number) FROM ethscriptions) AND NEW.transaction_index <= (SELECT MAX(transaction_index) FROM ethscriptions WHERE block_number = NEW.block_number)) THEN
            RAISE EXCEPTION 'New ethscription must be later in order';
          END IF;
          RETURN NEW;
        END;
        $$;


--
-- Name: check_facet_block_order(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_facet_block_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
        BEGIN
          IF (SELECT MAX(number) FROM facet_blocks) IS NOT NULL AND (NEW.number <> (SELECT MAX(number) + 1 FROM facet_blocks) OR NEW.parent_hash <> (SELECT block_hash FROM facet_blocks WHERE number = NEW.number - 1)) THEN
            RAISE EXCEPTION 'New block number must be equal to max block number + 1, or this must be the first block. Provided: new number = %, expected number = %, new parent hash = %, expected parent hash = %',
            NEW.number, (SELECT MAX(number) + 1 FROM facet_blocks), NEW.parent_hash, (SELECT block_hash FROM facet_blocks WHERE number = NEW.number - 1);
          END IF;
          RETURN NEW;
        END;
        $$;


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
    logs_bloom text NOT NULL,
    total_difficulty numeric(78,0),
    receipts_root character varying NOT NULL,
    extra_data character varying NOT NULL,
    withdrawals_root character varying NOT NULL,
    base_fee_per_gas bigint NOT NULL,
    nonce character varying NOT NULL,
    miner character varying NOT NULL,
    excess_blob_gas bigint,
    difficulty bigint NOT NULL,
    gas_limit bigint NOT NULL,
    gas_used bigint NOT NULL,
    parent_beacon_block_root character varying,
    size integer NOT NULL,
    transactions_root character varying NOT NULL,
    state_root character varying NOT NULL,
    mix_hash character varying NOT NULL,
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
    transaction_index integer NOT NULL,
    tx_type integer NOT NULL,
    nonce integer NOT NULL,
    input text NOT NULL,
    r character varying NOT NULL,
    s character varying NOT NULL,
    chain_id integer,
    v integer NOT NULL,
    gas bigint NOT NULL,
    max_priority_fee_per_gas numeric(78,0),
    from_address character varying NOT NULL,
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
-- Name: index_facet_transactions_on_tx_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_facet_transactions_on_tx_hash ON public.facet_transactions USING btree (tx_hash);


--
-- Name: eth_blocks trigger_check_eth_block_order; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_check_eth_block_order BEFORE INSERT ON public.eth_blocks FOR EACH ROW EXECUTE FUNCTION public.check_eth_block_order();


--
-- Name: ethscriptions trigger_check_ethscription_order; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_check_ethscription_order BEFORE INSERT ON public.ethscriptions FOR EACH ROW EXECUTE FUNCTION public.check_ethscription_order();


--
-- Name: facet_blocks trigger_check_facet_block_order; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_check_facet_block_order BEFORE INSERT ON public.facet_blocks FOR EACH ROW EXECUTE FUNCTION public.check_facet_block_order();


--
-- Name: ethscriptions fk_rails_104cee2b3d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscriptions
    ADD CONSTRAINT fk_rails_104cee2b3d FOREIGN KEY (block_number) REFERENCES public.eth_blocks(number) ON DELETE CASCADE;


--
-- Name: ethscriptions fk_rails_2accd8a448; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ethscriptions
    ADD CONSTRAINT fk_rails_2accd8a448 FOREIGN KEY (transaction_hash) REFERENCES public.eth_transactions(tx_hash) ON DELETE CASCADE;


--
-- Name: eth_calls fk_rails_2bd24c7340; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_calls
    ADD CONSTRAINT fk_rails_2bd24c7340 FOREIGN KEY (transaction_hash) REFERENCES public.eth_transactions(tx_hash) ON DELETE CASCADE;


--
-- Name: facet_transactions fk_rails_3134e9c482; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facet_transactions
    ADD CONSTRAINT fk_rails_3134e9c482 FOREIGN KEY (eth_transaction_hash) REFERENCES public.eth_transactions(tx_hash) ON DELETE CASCADE;


--
-- Name: facet_blocks fk_rails_31974ea46f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facet_blocks
    ADD CONSTRAINT fk_rails_31974ea46f FOREIGN KEY (eth_block_hash) REFERENCES public.eth_blocks(block_hash) ON DELETE CASCADE;


--
-- Name: facet_transactions fk_rails_46cb0d70d8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facet_transactions
    ADD CONSTRAINT fk_rails_46cb0d70d8 FOREIGN KEY (block_hash) REFERENCES public.facet_blocks(block_hash) ON DELETE CASCADE;


--
-- Name: facet_transaction_receipts fk_rails_bf9deceb3b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facet_transaction_receipts
    ADD CONSTRAINT fk_rails_bf9deceb3b FOREIGN KEY (transaction_hash) REFERENCES public.facet_transactions(tx_hash) ON DELETE CASCADE;


--
-- Name: eth_calls fk_rails_c8d48557a6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_calls
    ADD CONSTRAINT fk_rails_c8d48557a6 FOREIGN KEY (block_hash) REFERENCES public.eth_blocks(block_hash) ON DELETE CASCADE;


--
-- Name: eth_transactions fk_rails_db1761e6d4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eth_transactions
    ADD CONSTRAINT fk_rails_db1761e6d4 FOREIGN KEY (block_hash) REFERENCES public.eth_blocks(block_hash) ON DELETE CASCADE;


--
-- Name: facet_transaction_receipts fk_rails_ed7d5973ff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facet_transaction_receipts
    ADD CONSTRAINT fk_rails_ed7d5973ff FOREIGN KEY (block_hash) REFERENCES public.facet_blocks(block_hash) ON DELETE CASCADE;


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

