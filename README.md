# matrix-node

`matrix-node` is the **Derivation Node** in the Matrix ecosystem (an execution-only rollup on BNB Chain). It continuously reads L1 (BNB) blocks, extracts Matrix inputs from Inbox transactions (calldata), and **deterministically** derives an ordered L2 input stream / batches that an execution client (e.g., `matrix-geth`) consumes to produce L2 blocks and state.

> Forked from `0xFacet/facet-node` and adapted for Matrix.

---

## Role in the Matrix ecosystem

* **Inherits L1 ordering**: no standalone sequencer; L2 ordering strictly follows the transaction order in BNB blocks
* **Extracts Inbox inputs**: filters L1 blocks for transactions sent to the Inbox and parses the payload
* **Derives L2 inputs**: produces executable L2 batches / input stream and drives the execution client

In one sentence: **L1 handles inclusion & ordering, `matrix-node` handles extraction & derivation, and `matrix-geth` handles execution & state.**

---

## How it works

```text
Users/DApps
  -> send tx(calldata) to Inbox on BNB L1
BNB Chain (L1)
  -> inclusion + ordering + data availability
matrix-node (Derivation)
  -> read L1 blocks -> filter Inbox txs -> derive ordered L2 inputs/batches
matrix-geth (Execution)
  -> execute batches -> maintain state -> expose L2 RPC
```

---

## Quickstart (Docker/Compose)

> Use the compose files under `docker-compose/` (mainnet/testnet), depending on your setup.

```bash
git clone https://github.com/MatrixonBNB/Matrix-node.git
cd Matrix-node

cp .sample.env .env
# edit .env (at minimum: L1_RPC_URL, INBOX_ADDRESS, START_BLOCK)

docker compose up -d --build
docker compose logs -f
```

Example derivation start point (L1 block height you provided):

* `START_BLOCK=74301080`

---

## Key configuration (example fields; follow .sample.env)

* `L1_RPC_URL`: BNB Chain RPC endpoint
* `INBOX_ADDRESS`: Matrix Inbox address
* `START_BLOCK`: derivation start block (e.g., 74301080)
* `L1_CHAIN_ID`: 56 for the mainnet, 97 for the testnet
* `L2_CHAIN_ID`: 768945 for the mainnet, 768946 for the testnet
* (if using Engine API) `ENGINE_API_URL` / `JWT_SECRET`

---

## License

MIT. See `LICENSE`.
