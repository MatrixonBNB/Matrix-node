# Welcome to Facet Node!

### What is Facet Node?

`facet-node` works with `facet-geth` to trustlessly derive Facet state from Ethereum history. The system is heavily inspired by Optimism, with `facet-geth` forked from `op-geth` and `facet-node` modeled after `op-node`.

`facet-node` is pre-release software and subject to rapid development.

### The Basic Idea

Here's how it works:

1. `facet-node` examines each L1 block in order and traces all calls made in that block using `debug_traceBlockByNumber`.

2. For each successful call whose input data is a properly formatted Facet transaction, `facet-node` extracts the transaction information and combines it with other data to form a new transaction payload that `facet-geth` can understand (this is called a "Deposit Transaction").

3. `facet-node` constructs a Facet block with these Deposit transactions and sends the block to `facet-geth` using the [engine API](https://github.com/ethereum/execution-apis/tree/main/src/engine). This is the same API Ethereum consensus clients use to tell the execution layer about new blocks, so within the typical Ethereum model, `facet-node` functions as a consensus client.

`facet-node` is stateless. All data required to operate `facet-node` is stored in `facet-geth` or the `facet-node` git repository. This stateless design ensures that `facet-node` doesn't have to worry about keeping its state in sync with `facet-geth`.

## Facet V1 (Legacy) Migration

This stateless design is complicated by the need to import historical data from Facet V1. Facet V1 operated under a very different model and it's not possible to translate V1 data to V2 directly using only on-chain data. Because of this a small amount of outside data is required and this data has been included in this repository.

However, as Facet V1 will continue to be used until V2 launches, this data must be periodically refreshed (or looked up in real-time). Once V2 launches the V1 data will be frozen. For now the legacy data goes through block 20703687 on mainnet and 6661174 on Sepolia which should be enough for testing.

## Installation

1. Clone `facet-node`:
   ```
   git clone https://github.com/0xFacet/facet-node
   ```
   
   and `facet-geth`:
   ```
   git clone https://github.com/0xFacet/facet-geth
   ```
2. Facet's version of geth in on the `facet` branch, so `cd facet-geth && git checkout facet`.
 
 2.  Now `cd ../facet-node`

2. Install Ruby Version Manager (RVM) if not already installed:
   ```
   \curl -sSL https://get.rvm.io | bash -s stable
   ```
   
   If you encounter GPG issues, run:
   ```
   gpg2 --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDBd
   ```

3. Install Ruby 3.3.4:
   ```
   rvm install 3.3.4
   ```
   
   On macOS, if you encounter OpenSSL issues:
   ```
   rvm install 3.3.4 --with-openssl-dir=$(brew --prefix openssl@1.1)
   ```

4. Install required gems and dependencies:
   ```
   bundle install && npm i && pip install -r requirements.txt
   ```
   
4. Enable caching. Solidity compilation is slow and the output is cached in memcache so this will speed things up a lot:

   ```
   rails dev:cache
   ```

5. Install PostgreSQL (if not already installed):
   ```
   brew install postgresql
   ```

6. Install Memcached (if not already installed):
   ```
   brew install memcached
   ```

7. Set up environment variables. First copy the .sample.env files to .env and .env.development and .env.test:

    ```
    cp .sample.env .env && cp .sample.env.development .env.development && cp .sample.env.test .env.test
    ```
    
    Now edit the files. Here's what the variables are for:
    
    | Variable | Description |
    |----------|-------------|
    | `L1_RPC_URL` | The URL of your Ethereum RPC server. Facet blocks are derived from data that comes from this RPC endpoint. |
    | `BLOCK_IMPORT_BATCH_SIZE` | Number of blocks to import in each batch. This is how many simultaneous requests are made to the RPC endpoint. |
    | `L1_NETWORK` | The Ethereum network to derive blocks from. `sepolia` or `mainnet` |
    | `GETH_RPC_URL` | RPC URL for authenticated facet-geth connections. You can leave this as the default unless you plan to run multiple facet-geth instances simultaneously. |
    | `NON_AUTH_GETH_RPC_URL` | RPC URL for non-authenticated facet-geth connections. You can leave this as the default unless you plan to run multiple facet-geth instances simultaneously. |
    | `GETH_DISCOVERY_PORT` | Port used by facet-geth for peer discovery. You can leave this as the default unless you plan to run multiple facet-geth instances simultaneously. |
    | `JWT_SECRET` | Secret key for JWT authentication. **The value you put here must also go in `/tmp/jwtsecret` on your local machine** |
    | `DATABASE_URL` | URL your local postgresql db |
    | `L1_GENESIS_BLOCK` | The genesis block number. To sync Facet mainnet from genesis set it to 18684899. To sync Sepolia from genesis set it to 5193574. To test in Sepolia with current data, set it to the current block number. |
    | `V2_FORK_TIMESTAMP` | Timestamp for v2 fork. After this timestamp `facet-node` will use the new V2 logic to build blocks. Set to the same value as L1_GENESIS_BLOCK to skip the v1 import. |
    | `LOCAL_GETH_DIR` | Location of the directory into which you cloned facet-geth |
    | `FACET_V1_VM_DATABASE_URL` | (Optional) URL for v1 database, if available. You probably won't need this. |
    | `LEGACY_VALUE_ORACLE_URL` | URL for the legacy value oracle service. You can use one of the values from the sample. This is only necessary if you're doing a v1 import that extends beyond the legacy data included in the repo. |

8. Put your JWT_SECRET in `/tmp/jwtsecret` on your local machine:

    ```
    echo 0x... > /tmp/jwtsecret
    ```

9. Set up the local database:
   ```
   rails db:create db:migrate
   rails db:create db:migrate RAILS_ENV=test
   ```
   
10. Run the specs to ensure everything works. This might take a while as all the contracts must be compiled:
   ```
   rspec
   ```

## Using `facet-geth`

To use facet-geth to process blocks instead of just in a test:

1. From the `facet-node` directory, generate the geth initialization command. This will also set up your genesis.json file:
   ```
   bundle exec rake geth:init_command
   ```

4. Copy the command, cd back into `facet-geth`, and run it.

5. Finally, cd back into `facet-node` and start deriving Facet blocks from L1 blocks:
   ```
   bundle exec clockwork config/derive_facet_blocks.rb
   ```

You should now have `facet-node` and `facet-geth` set up and running!
