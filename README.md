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

#### Architecture: Two Meshes Connected by a Hub

This example demonstrates bridging between **two separate OFT meshes** via a **Hub chain**:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              MESH ARCHITECTURE                                  │
└─────────────────────────────────────────────────────────────────────────────────┘

    ┌───────────────────────────┐         ┌───────────────────────────┐
    │   NativeOFTAdapter Mesh   │         │  StargatePoolNative Mesh  │
    │                           │         │  (Stargate's native pools)│
    ├───────────────────────────┤         ├───────────────────────────┤
    │ • OP Sepolia (OFT)        │         │ • ETH Sepolia             │
    │ • ... other chains (OFT)  │         │ • ... other chains        │
    └─────────────┬─────────────┘         └─────────────┬─────────────┘
                  │                                     │
                  │         ┌─────────────────┐         │
                  │         │    HUB CHAIN    │         │
                  │         │ (Arb Sepolia)   │         │
                  │         ├─────────────────┤         │
                  └────────>│ NativeOFTAdapter│<────────┘
                            │ StargatePool    │
                            │ Composer        │
                            └─────────────────┘
```

**Key Concepts:**

| Term | Description |
|------|-------------|
| **NativeOFTAdapter** | Exists **only on the Hub chain**. Locks/unlocks native ETH and communicates with regular OFTs on peer chains. |
| **NativeOFTAdapter Mesh** | The NativeOFTAdapter (Hub) + regular OFTs on peer chains. Peers are standard OFTs that mint/burn, NOT NativeOFTAdapters. |
| **StargatePoolNative Mesh** | Stargate's existing native ETH pools. Already deployed and connected across many chains. |
| **Hub Chain** | The only chain with both a NativeOFTAdapter AND StargatePoolNative. This is where the Composer lives. |
| **Composer** | The `NativeStargateComposer` on the Hub that routes tokens between the two meshes. |

**Why a Hub?**
- NativeOFTAdapter only exists on **one chain** (the Hub) — peer chains have regular OFTs
- The Hub is special because it has access to **both** your NativeOFTAdapter AND Stargate's pool
- The Composer bridges the two: receives on one mesh, forwards to the other

These commands route through the NativeStargateComposer on Arbitrum Sepolia hub.

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         NativeStargateComposer Flow                             │
└─────────────────────────────────────────────────────────────────────────────────┘

  HOME CHAIN                    HUB CHAIN                      SPOKE CHAIN
  (OP Sepolia)                  (Arbitrum Sepolia)             (ETH Sepolia)
                                                              
  ┌─────────┐                   ┌──────────────────┐           ┌─────────────────┐
  │  MyOFT  │                   │ NativeOFTAdapter │           │ StargatePool    │
  │  (OFT)  │                   │ (NATIVE_OFT)     │           │ Native          │
  └────┬────┘                   └────────┬─────────┘           └────────┬────────┘
       │                                 │                              │
       │ 1. send()                       │                              │
       │    composeMsg = HopParams       │                              │
       │    (SendParam + hopQuote)       │                              │
       │ ───────────────────────────────>│                              │
       │                                 │                              │
       │                        ┌────────▼─────────┐                    │
       │                        │ NativeStargate   │                    │
       │                        │ Composer         │                    │
       │                        │                  │                    │
       │                        │ 2. lzCompose()   │                    │
       │                        │    decode params │                    │
       │                        │    route to      │                    │
       │                        │    STARGATE_POOL │                    │
       │                        └────────┬─────────┘                    │
       │                                 │                              │
       │                   ┌─────────────▼──────────────┐               │
       │                   │ StargatePoolNative         │               │
       │                   │ (STARGATE_POOL)            │               │
       │                   └─────────────┬──────────────┘               │
       │                                 │                              │
       │                                 │ 3. send() to destination     │
       │                                 │    using pre-quoted fee      │
       │                                 │ ────────────────────────────>│
       │                                 │                              │
       │                                 │                     4. Receive│
       │                                 │                        native │
       │                                 │                        ETH    │
       │                                 │                              ▼

───────────────────────────────────────────────────────────────────────────────────
  REVERSE FLOW: Stargate → Composer → NativeOFT mesh
───────────────────────────────────────────────────────────────────────────────────

       │                                 │                              │
       │                                 │    1. send() from Stargate   │
       │                                 │<──────────────────────────────
       │                                 │                              │
       │                        ┌────────▼─────────┐                    │
       │                        │ Composer routes  │                    │
       │                        │ to NATIVE_OFT    │                    │
       │                        └────────┬─────────┘                    │
       │                                 │                              │
       │    2. lzReceive()               │                              │
       │<────────────────────────────────                               │
       │                                 │                              │
       ▼                                 │                              │
  Receive OFT                            │                              │
  tokens                                 │                              │
```

**Routing Logic:**
- If compose triggered by `NATIVE_OFT` → forward to `STARGATE_POOL`
- If compose triggered by `STARGATE_POOL` → forward to `NATIVE_OFT`

> **Note:** The second hop fee is quoted off-chain before sending. This avoids calling `quoteSend()` in the `lzCompose` receive path. If the fee deviates significantly, the compose will revert early and the message can be retried with a fresh quote.

### Compose Message Layout (HopParams)

When performing a multi-hop send, the `composeMsg` field contains encoded `HopParams` that the Composer decodes to execute the second hop. This structure is VM-agnostic in concept but must be encoded according to each VM's conventions.

```
┌───────────────────────────────────────── HopParams ─────────────────────────────────────────┐
│                                                                                             │
│  ┌──────────────────────────────── SendParam ────────────────────────────────┐ ┌─────────┐  │
│  │                                                                           │ │Messaging│  │
│  │ ┌────────┬────────┬──────────┬───────────┬───────────┬─────────┬────────┐ │ │  Fee    │  │
│  │ │ dstEid │   to   │ amountLD │minAmountLD│ extraOpts │composeMs│ oftCmd │ │ │┌───────┐│  │
│  │ │        │        │          │           │           │         │        │ │ ││native ││  │
│  │ │ 4 B    │ 32 B   │  32 B    │   32 B    │   var B   │  var B  │ var B  │ │ ││Fee    ││  │
│  │ │        │        │  (= 0)   │   (= 0)   │           │  (= 0x) │ (=0x)  │ │ ││ 32 B  ││  │
│  │ └────────┴────────┴──────────┴───────────┴───────────┴─────────┴────────┘ │ │├───────┤│  │
│  │                                                                           │ ││lzToken││  │
│  │  dstEid     = Final destination endpoint ID                               │ ││Fee    ││  │
│  │  to         = Final recipient address (zero-padded)                       │ ││ 32 B  ││  │
│  │  amountLD   = Set to 0; Composer overrides with received amount           │ ││(= 0)  ││  │
│  │  minAmountLD= Set to 0; Composer handles slippage                         │ │└───────┘│  │
│  │  extraOpts  = Options for second hop (e.g., lzReceive gas)                │ │         │  │
│  │  composeMsg = Empty (0x) for final destination                            │ │ 64 B    │  │
│  │  oftCmd     = Empty (0x)                                                  │ │ total   │  │
│  │                                                                           │ │         │  │
│  └───────────────────────────────────────────────────────────────────────────┘ └─────────┘  │
│                                                                                             │
│  Key Notes:                                                                                 │
│  • amountLD = 0 in message → Composer overrides with actual received amount                 │
│  • Fee is pre-quoted off-chain → Avoids quoteSend() in receive path                         │
│  • If fee deviates at execution → Send reverts, can be retried via retry()                  │
│                                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

#### Solidity Encoding (EVM)

In `tasks/sendEvm.ts`, the HopParams is ABI-encoded as follows:

```typescript
// Encode HopParams: tuple of (SendParam, MessagingFee)
const composeMsg = ethers.utils.defaultAbiCoder.encode(
    ['tuple(tuple(uint32,bytes32,uint256,uint256,bytes,bytes,bytes),tuple(uint256,uint256))'],
    [
        [
            [dstEid, addressToBytes32(to), 0, 0, secondHopOptions, '0x', '0x'], // SendParam
            [secondHopQuote.nativeFee, secondHopQuote.lzTokenFee],              // MessagingFee
        ],
    ]
)
```

The Composer decodes this in Solidity using:

```solidity
HopParams memory hopParams = abi.decode(hopParamsBytes, (HopParams));
```

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
