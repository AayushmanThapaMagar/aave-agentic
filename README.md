# Aave Position Guardian

A read-only integration and automation layer for Aave V4. This repository is starting with Stage 1: verified Spoke-scoped position reads on Ethereum mainnet.

## Stage 1 scope

- Ethereum V4 Hub and standard Spoke address registry.
- Canonical Aave V4 `ISpoke` and `IHubBase` interface dependencies.
- Read-only reserve enumeration, reserve configuration, and dynamic reserve configuration.
- Spoke-side position retrieval: supplied assets, total debt, collateral status, and borrowing status.
- Native V4 account data and health factor retrieval.
- Hub-side asset metadata and aggregate accounting reads.
- Unit tests and opt-in Ethereum mainnet fork tests.

No supply, withdraw, borrow, repay, collateral management, liquidation, keeper, backend, frontend, or AI agent execution is implemented.

## Validation status

The Stage 1 source, unit tests, fork tests, and read script have been authored, but this handoff has **not** been compiled or executed: the build environment used to prepare it did not contain Foundry (`forge`, `cast`, `anvil`) or a Solidity compiler, and no Ethereum RPC credential was available. Do not treat the milestone as green or production-ready until dependency installation, formatting, compilation, unit tests, proxy implementation verification, and the mainnet fork suite all complete successfully. The optional real-user fork test also requires `FORK_USER` to be set to a known account with a Main Spoke position.

## Architecture facts

Aave V4 separates shared liquidity accounting in Hubs from user-facing borrowing and collateral risk in Spokes. Each Spoke reserve identifies its Hub and Hub asset ID; reserve risk configuration and user health are evaluated within that Spoke. Aave's Ethereum Main Spoke is the first target, but the adapter is parameterized by Spoke address.

Guardian calls `ISpoke.getUserAccountData(user)` and returns Aave's native account data instead of implementing V3 accounting or reproducing V4 health-factor arithmetic. It also reports both the reserve's latest dynamic configuration key and the user's stored position configuration key. These can differ: the user account calculation uses the user's position configuration, not an assumption that every existing position has already been refreshed to the newest reserve key.

Per-reserve amounts are returned in the underlying asset's raw units. `getUserSuppliedAssets` resolves the user's supplied shares through the Hub; `getUserTotalDebt` includes drawn and premium debt using the protocol getter. Account values are not token amounts: `healthFactor` is WAD (1e18 = 1.0), `totalCollateralValue` uses Aave's `Value` unit, and `totalDebtValueRay` is scaled by RAY. Preserve the raw fields and protocol scales in storage.

Hub-wide `getAddedAssets`, `getAssetTotalOwed`, and `getAssetLiquidity` are Hub/asset accounting values. They must not be misrepresented as the balance or debt of an individual Spoke or user. The Spoke position is authoritative for user-level position amounts.

## Source and deployment compatibility gate

The project pins Aave's official `v0.5.11` source tag for interface imports and `forge-std` `v1.17.0` for tests. A source tag is not, by itself, proof that a deployed proxy currently runs bytecode compiled from that tag. Ethereum's Main Spoke is a proxy, so the fork integration test is a mandatory ABI and state compatibility gate before treating this adapter as production-ready. Re-check the proxy implementation slot / upgrade events and rerun fork tests on every release. Do not silently substitute interfaces from a different V4 source version.

Ethereum's Main Spoke is an upgradeable EIP-1967 proxy. Extract the implementation slot and implementation runtime code hash with Cast:

```bash
export MAIN_SPOKE=0x94e7A5dCbE816e498b89aB752661904E2F56c485
export IMPLEMENTATION_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
export IMPLEMENTATION_WORD=$(cast storage "$MAIN_SPOKE" "$IMPLEMENTATION_SLOT" --rpc-url "$ETHEREUM_RPC_URL")
export IMPLEMENTATION=0x${IMPLEMENTATION_WORD: -40}
export IMPLEMENTATION_CODE=$(cast code "$IMPLEMENTATION" --rpc-url "$ETHEREUM_RPC_URL")
export IMPLEMENTATION_CODE_HASH=$(cast keccak "$IMPLEMENTATION_CODE")
printf 'implementation=%s\ncode_hash=%s\n' "$IMPLEMENTATION" "$IMPLEMENTATION_CODE_HASH"
```

For reproducible evidence, query the same finalized block used by the fork suite (use Cast's `--block <FINALIZED_BLOCK>` option where supported) and record the block number alongside the output. This verifies the proxy slot and deployed bytecode hash at that block; it does not prove source equivalence without matching verified source, compiler settings, and metadata. The live implementation address and code hash have not yet been recorded in this repository.

The address registry is an Ethereum-only snapshot derived from the Aave DAO address book. Aave's official changelog also records V4 deployments on Avalanche, Arc, and Base; those networks are not supported by this registry or this first fork suite. Add each network only after verifying its chain ID, Hub/Spoke addresses, proxy implementation, and interface compatibility independently.

## Prerequisites

- Foundry v1.8.3 or newer (`forge-std` v1.17.0 requires this minimum).
- Git with submodule support.
- Ethereum mainnet RPC URL for fork tests and live reads.

The project currently uses Solidity `0.8.28` and Cancun EVM settings, consistent with the pinned Aave V4 source configuration.

## Initialize dependencies

From the repository root:

```bash
git init -b main
cp .env.example .env
# Edit .env and set ETHEREUM_RPC_URL and POSITION_USER.
forge install aave/aave-v4@v0.5.11 --no-commit
forge install foundry-rs/forge-std@v1.17.0 --no-commit
```

After installation, record the resolved dependency commits:

```bash
git -C lib/aave-v4 rev-parse HEAD
git -C lib/forge-std rev-parse HEAD
```

Commit the Foundry submodule gitlinks along with `.gitmodules`; do not replace the pinned revisions with floating branches. Aave's source license is distinct from Guardian-authored code; read `docs/security.md` before any distribution or commercial / production use.

After the dependency commits have been recorded and the checks below pass, prepare the initial GitHub commit:

```bash
git add .
git status --short
git commit -m "chore: bootstrap Aave V4 read-only integration"
git remote add origin https://github.com/<YOUR_GITHUB_USERNAME>/aave-position-guardian.git
git push -u origin main
```

## Build and unit tests

```bash
forge fmt --check
forge build
forge test --match-path 'test/unit/*.t.sol' -vvv
```

## Ethereum mainnet fork tests

Set `ETHEREUM_RPC_URL` in `.env`. The fork suite checks that the registered Main Spoke has code, lists reserves, returns a non-zero target-health-factor setting, and that each listed reserve's Hub/asset metadata agrees with the Spoke record. This also exercises the exact interface selectors and tuple shapes used by the adapter.

```bash
forge test --match-path 'test/fork/*.t.sol' -vvv
```

To test an actual user position, set `FORK_USER` to an address that has supplied or borrowed assets on the Aave V4 Ethereum Main Spoke. The corresponding test is skipped when `FORK_USER` is blank and fails if the configured address has no non-empty Main Spoke reserve position.

## Read a live Main Spoke position

Set `POSITION_USER` in your shell or `.env` to the account to inspect:

```bash
export POSITION_USER=0xYourUserAddress
forge script script/ReadMainSpokePosition.s.sol --rpc-url "$ETHEREUM_RPC_URL" -vvv
```

The script does not call `startBroadcast` and does not submit a transaction. It performs a local read-only simulation and reports raw on-chain asset units, token decimals, Hub address, Hub asset ID, account values, and the V4 health factor in WAD. Divide `healthFactor` by `1e18` for the familiar decimal presentation; do not convert raw `totalCollateralValue` or `totalDebtValueRay` to token units.

Optionally override the target Spoke with `SPOKE_ADDRESS`, but only use an official V4 Spoke address on the selected network.

## Test interpretation

- Unit tests use ABI-compatible mocks implementing only the official selectors called by this adapter.
- Fork tests are skipped when `ETHEREUM_RPC_URL` is not configured.
- A live user-position test requires a known `FORK_USER`; no real user address or live chain result is hardcoded.
- A passing local unit suite is not evidence that a live proxy's current implementation matches the pinned interface dependency. The fork suite is required for that determination.

## Address provenance

The Ethereum registry is a snapshot of `AaveV4Ethereum.sol` from the Aave DAO address book release `v4.75.3` (2026-10-27), cross-checked against the official Aave protocol addresses documentation. The current standard ISpoke getter enumerates thirteen standard Spokes; Treasury is exposed as `ITreasurySpoke` separately, so it is intentionally omitted from this typed standard-Spoke list. The address-book source also contains additional tokenization Spokes, which are outside the first read path. Hub addresses are curated in the address book; each reserve’s actual Hub and Hub asset ID are then read from that Spoke’s `getReserve` result. The Hub base interface exposes per-asset and per-Spoke accounting getters, but no general on-chain enumerator for all Spokes, so we do not invent one.

Refresh and review the registry against a pinned `aave-address-book` release before every deployment. Do not assume this list applies to other networks.

## Repository structure

```text
src/
  adapters/       Read-only Spoke and Hub adapter
  registry/       Ethereum V4 deployment registry
  interfaces/     Reserved for Guardian-owned integration interfaces

test/
  unit/           Mock-based tests
  fork/           Ethereum mainnet fork tests
  mocks/          Minimal ISpoke / IHubBase test doubles
script/           Read-only inspection script
lib/              Foundry dependencies (git submodules)
docs/             Architecture, threat model, and security notes
```
