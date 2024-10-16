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


--
-- Name: check_legacy_value_conflict(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_legacy_value_conflict() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      BEGIN
        IF EXISTS (
          SELECT 1
          FROM legacy_value_mappings
          WHERE legacy_value = NEW.legacy_value
            AND new_value <> NEW.new_value
        ) THEN
          RAISE EXCEPTION 'Conflict: legacy_value % is already mapped to a different new_value', NEW.legacy_value;
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
    base_fee_per_gas bigint,
    parent_beacon_block_root character varying,
    mix_hash character varying,
    parent_hash character varying NOT NULL,
    "timestamp" bigint NOT NULL,
    imported_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_4a3f27d5e8 CHECK (((mix_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_69f1818bcd CHECK (((parent_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_a5a0dc024d CHECK (((parent_beacon_block_root)::text ~ '^0x[a-f0-9]{64}$'::text)),
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
    size integer,
    state_root character varying NOT NULL,
    "timestamp" bigint NOT NULL,
    transactions_root character varying,
    prev_randao character varying NOT NULL,
    eth_block_timestamp bigint,
    eth_block_base_fee_per_gas bigint,
    sequence_number integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_e289f61f63 CHECK (((block_hash)::text ~ '^0x[a-f0-9]{64}$'::text)),
    CONSTRAINT chk_rails_e8cae93f42 CHECK (((prev_randao)::text ~ '^0x[a-f0-9]{64}$'::text)),
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
    eth_transaction_hash character varying,
    eth_call_index integer,
    block_hash character varying NOT NULL,
    block_number bigint NOT NULL,
    deposit_receipt_version character varying NOT NULL,
    from_address character varying NOT NULL,
    gas_limit bigint NOT NULL,
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
-- Name: l1_smart_contracts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.l1_smart_contracts (
    id bigint NOT NULL,
    address character varying NOT NULL,
    block_number bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_rails_ef594e2006 CHECK (((address)::text ~ '^0x[0-9a-f]{40}$'::text))
);


--
-- Name: l1_smart_contracts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.l1_smart_contracts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: l1_smart_contracts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.l1_smart_contracts_id_seq OWNED BY public.l1_smart_contracts.id;


--
-- Name: legacy_value_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.legacy_value_mappings (
    id bigint NOT NULL,
    legacy_value character varying NOT NULL,
    new_value character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT new_value_pattern_check CHECK ((((new_value)::text ~ '^0x[a-f0-9]{64}$'::text) OR ((new_value)::text ~ '^0x[a-f0-9]{40}$'::text)))
);


--
-- Name: legacy_value_mappings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.legacy_value_mappings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: legacy_value_mappings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.legacy_value_mappings_id_seq OWNED BY public.legacy_value_mappings.id;


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
-- Name: l1_smart_contracts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l1_smart_contracts ALTER COLUMN id SET DEFAULT nextval('public.l1_smart_contracts_id_seq'::regclass);


--
-- Name: legacy_value_mappings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legacy_value_mappings ALTER COLUMN id SET DEFAULT nextval('public.legacy_value_mappings_id_seq'::regclass);


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
-- Name: l1_smart_contracts l1_smart_contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.l1_smart_contracts
    ADD CONSTRAINT l1_smart_contracts_pkey PRIMARY KEY (id);


--
-- Name: legacy_value_mappings legacy_value_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.legacy_value_mappings
    ADD CONSTRAINT legacy_value_mappings_pkey PRIMARY KEY (id);


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
-- Name: index_facet_blocks_on_block_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_facet_blocks_on_block_hash ON public.facet_blocks USING btree (block_hash);


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
-- Name: index_facet_transaction_receipts_on_transaction_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_facet_transaction_receipts_on_transaction_index ON public.facet_transaction_receipts USING btree (transaction_index);


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
-- Name: index_l1_smart_contracts_on_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_l1_smart_contracts_on_address ON public.l1_smart_contracts USING btree (address);


--
-- Name: index_legacy_value_mappings_on_legacy_value; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_legacy_value_mappings_on_legacy_value ON public.legacy_value_mappings USING btree (legacy_value);


--
-- Name: eth_blocks trigger_check_eth_block_order; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_check_eth_block_order BEFORE INSERT ON public.eth_blocks FOR EACH ROW EXECUTE FUNCTION public.check_eth_block_order();


--
-- Name: facet_blocks trigger_check_facet_block_order; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_check_facet_block_order BEFORE INSERT ON public.facet_blocks FOR EACH ROW EXECUTE FUNCTION public.check_facet_block_order();


--
-- Name: legacy_value_mappings trigger_check_legacy_value_conflict; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_check_legacy_value_conflict BEFORE INSERT OR UPDATE ON public.legacy_value_mappings FOR EACH ROW EXECUTE FUNCTION public.check_legacy_value_conflict();


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
-- Name: facet_transaction_receipts fk_rails_ed7d5973ff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facet_transaction_receipts
    ADD CONSTRAINT fk_rails_ed7d5973ff FOREIGN KEY (block_hash) REFERENCES public.facet_blocks(block_hash) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20240924215928'),
('20240813133726'),
('20240627143934'),
('20240627143407'),
('20240627143108'),
('20240627142124');

