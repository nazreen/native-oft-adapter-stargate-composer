<p align="center">
  <a href="https://layerzero.network">
    <img alt="LayerZero" style="width: 400px" src="https://docs.layerzero.network/img/LayerZero_Logo_White.svg"/>
  </a>
</p>

<p align="center">
  <a href="https://layerzero.network" style="color: #a77dff">Homepage</a> | <a href="https://docs.layerzero.network/" style="color: #a77dff">Docs</a> | <a href="https://layerzero.network/developers" style="color: #a77dff">Developers</a>
</p>

<h1 align="center">NativeOFTAdapter + NativeStargateComposer Example</h1>

<p align="center">
  <a href="https://docs.layerzero.network/v2/developers/evm/oft/adapter" style="color: #a77dff">Quickstart</a> | <a href="https://docs.layerzero.network/contracts/oapp-configuration" style="color: #a77dff">Configuration</a> | <a href="https://docs.layerzero.network/contracts/options" style="color: #a77dff">Message Execution Options</a> | <a href="https://docs.layerzero.network/contracts/endpoint-addresses" style="color: #a77dff">Endpoint Addresses</a>
</p>

<p align="center">Template project for getting started with LayerZero's <code>NativeOFTAdapter</code> contract development.</p>

WARNING: this example code is not audited. You should get them audited before deploying to production.

## 1) Developing Contracts

#### Installing dependencies

We recommend using `pnpm` as a package manager (but you can of course use a package manager of your choice):

```bash
pnpm install
```

#### Compiling your contracts

This project supports both `hardhat` and `forge` compilation. By default, the `compile` command will execute both:

```bash
pnpm compile
```

If you prefer one over the other, you can use the tooling-specific commands:

```bash
pnpm compile:forge
pnpm compile:hardhat
```

Or adjust the `package.json` to for example remove `forge` build:

```diff
- "compile": "$npm_execpath run compile:forge && $npm_execpath run compile:hardhat",
- "compile:forge": "forge build",
- "compile:hardhat": "hardhat compile",
+ "compile": "hardhat compile"
```

#### Running tests

Similarly to the contract compilation, we support both `hardhat` and `forge` tests. By default, the `test` command will execute both:

```bash
pnpm test
```

If you prefer one over the other, you can use the tooling-specific commands:

```bash
pnpm test:forge
pnpm test:hardhat
```

Or adjust the `package.json` to for example remove `hardhat` tests:

```diff
- "test": "$npm_execpath test:forge && $npm_execpath test:hardhat",
- "test:forge": "forge test",
- "test:hardhat": "$npm_execpath hardhat test"
+ "test": "forge test"
```

## 2) Deploying Contracts

Set up deployer wallet/account:

- Rename `.env.example` -> `.env`
- Choose your preferred means of setting up your deployer wallet/account:

```
MNEMONIC="test test test test test test test test test test test junk"
or...
PRIVATE_KEY="0xabc...def"
```

- Fund this address with the corresponding chain's native tokens you want to deploy to.

### Deploy All Contracts

To deploy all contracts to your desired blockchains, run:

```bash
npx hardhat lz:deploy
```

### Deploy Specific Contracts

```bash
# Deploy NativeOFTAdapter to Arbitrum Sepolia (hub)
pnpm hardhat deploy --network arbitrum-sepolia --tags MyNativeOFTAdapter

# Deploy OFT to Optimism Sepolia (home)
pnpm hardhat deploy --network optimism-sepolia --tags MyOFT

# Deploy NativeStargateComposer to Arbitrum Sepolia (hub)
# Note: Update STARGATE_POOL_NATIVE address in deploy/NativeStargateComposer.ts first
pnpm hardhat deploy --network arbitrum-sepolia --tags NativeStargateComposer
```

> If you need initial tokens on testnet for the EVM OFT, open `contracts/MyOFT.sol` and uncomment `_mint(msg.sender, 100000 * (10 ** 18));` in the constructor. Ensure you remove this line for production.

More information about available CLI arguments can be found using the `--help` flag:

```bash
npx hardhat lz:deploy --help
```

## 3) Wire

```bash
npx hardhat lz:oapp:wire --oapp-config layerzero.config.ts
```

## 4) Send

### Direct Sends (No Hop)

```bash
# Native Arb to OFT OP
npx hardhat lz:oft:send --amount 0.005 --src-eid 40231 --to <EVM_RECIPIENT> --dst-eid 40232 --extra-lz-receive-options "80000,0"

# OFT OP to Native Arb
npx hardhat lz:oft:send --amount 0.001 --src-eid 40232 --to <EVM_RECIPIENT> --dst-eid 40231 --extra-lz-receive-options "80000,0"
```

> `80000` as the gas value is sufficient for most EVM chains. For production, you should profile the gas usage of your pathways.

### Multi-Hop Sends (Via Composer)

These commands route through the NativeStargateComposer on Arbitrum Sepolia hub.

> **Note:** The second hop fee is quoted off-chain before sending. This avoids calling `quoteSend()` in the `lzCompose` receive path. If the fee deviates significantly, the compose will revert early and the message can be retried with a fresh quote.

```bash
# OP (Home OFT) to Ethereum (StargatePoolNative)
pnpm hardhat lz:oft:send \
  --src-eid 40232 \
  --dst-eid 40161 \
  --amount 0.001 \
  --to <EVM_RECIPIENT> \
  --extra-lz-receive-options "200000,0" \
  --extra-lz-compose-options "0,500000,15000000000000000"

# Ethereum (StargatePoolNative) to OP (Home OFT)
pnpm hardhat lz:oft:send \
  --src-eid 40161 \
  --dst-eid 40232 \
  --amount 0.001 \
  --min-amount 0.00095 \
  --to <EVM_RECIPIENT> \
  --extra-lz-receive-options "200000,0" \
  --extra-lz-compose-options "0,500000,15000000000000000"
```

**Options breakdown:**
- `--extra-lz-receive-options "200000,0"` → 200k gas for lzReceive
- `--extra-lz-compose-options "0,500000,15000000000000000"` → index 0, 500k gas, 0.015 ETH value for lzCompose
- `--min-amount` → Required for Stargate sends to allow for pool fees/slippage

## 5) Verify Contracts

```bash
npx @layerzerolabs/verify-contract \
  --network arbitrum-sepolia \
  --deployments ./deployments \
  --api-url "https://api.etherscan.io/v2/api?chainid=421614" \
  -k <ETHERSCAN_API_KEY>
```

By following these steps, you can focus more on creating innovative omnichain solutions and less on the complexities of cross-chain communication.

<br></br>

<p align="center">
  Join our <a href="https://layerzero.network/community" style="color: #a77dff">community</a>! | Follow us on <a href="https://x.com/LayerZero_Labs" style="color: #a77dff">X (formerly Twitter)</a>
</p>
