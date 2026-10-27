// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ISpoke} from "aave-v4/src/spoke/interfaces/ISpoke.sol";
import {SpokePositionReader} from "aave-position-guardian/adapters/SpokePositionReader.sol";
import {AaveV4EthereumRegistry} from "aave-position-guardian/registry/AaveV4EthereumRegistry.sol";

contract MainnetMainSpokeForkTest is Test {
  bytes32 internal constant EIP1967_IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  SpokePositionReader internal reader;

  function setUp() public {
    string memory rpcUrl = vm.envOr("ETHEREUM_RPC_URL", string(""));
    if (bytes(rpcUrl).length == 0) vm.skip(true);
    vm.createSelectFork(rpcUrl);
    reader = new SpokePositionReader();
  }

  function testForkMainSpokeHasCodeAndListedReserves() public {
    assertEq(block.chainid, 1, "fork must be Ethereum mainnet");
    address mainSpoke = AaveV4EthereumRegistry.MAIN_SPOKE;
    assertGt(mainSpoke.code.length, 0, "Main Spoke has no code at registry address");
    bytes32 implementationWord = vm.load(mainSpoke, EIP1967_IMPLEMENTATION_SLOT);
    address implementation = address(uint160(uint256(implementationWord)));
    assertTrue(implementation != address(0), "Main Spoke implementation slot is empty");
    assertGt(implementation.code.length, 0, "Main Spoke implementation has no code");

    uint256 reserveCount = ISpoke(mainSpoke).getReserveCount();
    assertGt(reserveCount, 0, "Main Spoke has no listed reserves");

    ISpoke.UserAccountData memory emptyAccountData = ISpoke(mainSpoke).getUserAccountData(
      address(0)
    );
    assertEq(emptyAccountData.healthFactor, type(uint256).max);
    assertEq(emptyAccountData.totalCollateralValue, 0);
    assertEq(emptyAccountData.totalDebtValueRay, 0);

    ISpoke.LiquidationConfig memory liquidationConfig = ISpoke(mainSpoke).getLiquidationConfig();
    assertGt(liquidationConfig.targetHealthFactor, 0, "unexpected zero target health factor");

    SpokePositionReader.ReserveInfo[] memory reserves = reader.readSpokeReserves(mainSpoke);
    assertEq(reserves.length, reserveCount);

    for (uint256 i; i < reserves.length; ++i) {
      assertTrue(reserves[i].underlying != address(0), "reserve underlying is zero");
      assertGt(reserves[i].hub.code.length, 0, "reserve Hub has no code");
      assertLt(reserves[i].collateralFactor, 10_000, "collateral factor must be below 100%");
      assertGe(reserves[i].maxLiquidationBonus, 10_000, "invalid max liquidation bonus");
      assertLe(reserves[i].liquidationFee, 10_000, "liquidation fee exceeds 100%");

      SpokePositionReader.HubAssetSnapshot memory hubAsset = reader.readHubAsset(
        reserves[i].hub,
        reserves[i].hubAssetId
      );
      assertEq(hubAsset.underlying, reserves[i].underlying, "Spoke/Hub underlying mismatch");
      assertEq(hubAsset.decimals, reserves[i].decimals, "Spoke/Hub decimals mismatch");
    }
  }

  /// @dev Supply FORK_USER in .env to assert against an actual user with a Main Spoke position.
  function testForkReadsConfiguredRealUserPosition() public {
    address user = vm.envOr("FORK_USER", address(0));
    if (user == address(0)) vm.skip(true);

    SpokePositionReader.PositionSnapshot memory snapshot = reader.readPosition(
      AaveV4EthereumRegistry.MAIN_SPOKE,
      user
    );

    assertEq(snapshot.chainId, 1);
    assertEq(snapshot.spoke, AaveV4EthereumRegistry.MAIN_SPOKE);
    assertEq(snapshot.user, user);
    assertGt(snapshot.reserves.length, 0, "FORK_USER has no non-empty Main Spoke reserves");
    assertGt(snapshot.accountData.healthFactor, 0, "unexpected zero health factor");

    bool foundBalance;
    for (uint256 i; i < snapshot.reserves.length; ++i) {
      if (
        snapshot.reserves[i].suppliedAssets > 0 || snapshot.reserves[i].borrowedAssets > 0
      ) {
        foundBalance = true;
        break;
      }
    }
    assertTrue(foundBalance, "FORK_USER has no supplied or borrowed assets on Main Spoke");
  }
}
