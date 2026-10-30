// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ISpoke} from "aave-v4/src/spoke/interfaces/ISpoke.sol";
import {SpokePositionReader} from "aave-position-guardian/adapters/SpokePositionReader.sol";
import {MockSpoke} from "../mocks/MockSpoke.sol";
import {MockHub} from "../mocks/MockHub.sol";

contract SpokePositionReaderTest is Test {
  SpokePositionReader internal reader;
  MockSpoke internal spoke;
  MockHub internal mockHub;
  address internal user = makeAddr("position-owner");
  address internal hub = makeAddr("hub");
  address internal tokenA = makeAddr("token-a");
  address internal tokenB = makeAddr("token-b");
  address internal tokenC = makeAddr("token-c");

  function setUp() public {
    reader = new SpokePositionReader();
    spoke = new MockSpoke();
    mockHub = new MockHub();
    spoke.addReserve(tokenA, hub, 4, 18);
    spoke.addReserve(tokenB, hub, 7, 6);
    spoke.addReserve(tokenC, hub, 9, 18);
    spoke.setUserAccountData(
      user,
      ISpoke.UserAccountData({
        riskPremium: 0,
        avgCollateralFactor: 0,
        healthFactor: type(uint256).max,
        totalCollateralValue: 0,
        totalDebtValueRay: 0,
        activeCollateralCount: 0,
        borrowCount: 0
      })
    );
  }

  function testReadReturnsSpokeNativeAccountDataAndNonEmptyReserves() public {
    spoke.setUserReserve(0, user, 3 ether, 0, true, false);
    spoke.setUserReserve(1, user, 0, 125e6, false, true);
    // An inactive reserve must not be included.
    spoke.setUserReserve(2, user, 0, 0, false, false);

    ISpoke.UserAccountData memory expected = ISpoke.UserAccountData({
      riskPremium: 125,
      avgCollateralFactor: 8e17,
      healthFactor: 15e17,
      totalCollateralValue: 3_000e26,
      totalDebtValueRay: 2_000e26 * 1e27,
      activeCollateralCount: 1,
      borrowCount: 1
    });
    spoke.setUserAccountData(user, expected);

    SpokePositionReader.PositionSnapshot memory snapshot = reader.readPosition(
      address(spoke), user
    );

    assertEq(snapshot.chainId, block.chainid);
    assertEq(snapshot.blockNumber, block.number);
    assertEq(snapshot.spoke, address(spoke));
    assertEq(snapshot.user, user);
    assertEq(snapshot.accountData.healthFactor, expected.healthFactor);
    assertEq(snapshot.accountData.totalCollateralValue, expected.totalCollateralValue);
    assertEq(snapshot.liquidationConfig.targetHealthFactor, 0);
    assertEq(snapshot.reserves.length, 2);

    assertEq(snapshot.reserves[0].reserveId, 0);
    assertEq(snapshot.reserves[0].underlying, tokenA);
    assertEq(snapshot.reserves[0].hub, hub);
    assertEq(snapshot.reserves[0].hubAssetId, 4);
    assertEq(snapshot.reserves[0].decimals, 18);
    assertEq(snapshot.reserves[0].suppliedAssets, 3 ether);
    assertTrue(snapshot.reserves[0].collateralEnabled);
    assertFalse(snapshot.reserves[0].borrowing);

    assertEq(snapshot.reserves[1].reserveId, 1);
    assertEq(snapshot.reserves[1].underlying, tokenB);
    assertEq(snapshot.reserves[1].decimals, 6);
    assertEq(snapshot.reserves[1].borrowedAssets, 125e6);
    assertFalse(snapshot.reserves[1].collateralEnabled);
    assertTrue(snapshot.reserves[1].borrowing);
  }

  function testSuppliedAssetIsIncludedEvenWhenNotEnabledAsCollateral() public {
    spoke.setUserReserve(2, user, 1 ether, 0, false, false);

    SpokePositionReader.PositionSnapshot memory snapshot = reader.readPosition(
      address(spoke), user
    );

    assertEq(snapshot.reserves.length, 1);
    assertEq(snapshot.reserves[0].suppliedAssets, 1 ether);
    assertFalse(snapshot.reserves[0].collateralEnabled);
  }

  function testEmptyPositionReturnsEmptyReserveArray() public {
    SpokePositionReader.PositionSnapshot memory snapshot = reader.readPosition(
      address(spoke), user
    );
    assertEq(snapshot.reserves.length, 0);
    assertEq(snapshot.accountData.healthFactor, type(uint256).max);
  }


  function testReadHubAssetReturnsCanonicalUnderlyingAndAccounting() public {
    mockHub.setAsset(4, MockHub.AssetData({
      underlying: tokenA,
      decimals: 18,
      availableLiquidity: 25 ether,
      totalOwed: 10 ether,
      totalAdded: 40 ether
    }));

    SpokePositionReader.HubAssetSnapshot memory snapshot = reader.readHubAsset(
      address(mockHub), 4
    );

    assertEq(snapshot.hub, address(mockHub));
    assertEq(snapshot.assetId, 4);
    assertEq(snapshot.underlying, tokenA);
    assertEq(snapshot.decimals, 18);
    assertEq(snapshot.availableLiquidity, 25 ether);
    assertEq(snapshot.totalOwed, 10 ether);
    assertEq(snapshot.totalAdded, 40 ether);
  }

  function testReadSpokeReserveCatalogReturnsReserveAndRiskConfiguration() public {
    spoke.setUserReserve(0, user, 1 ether, 0, true, false);
    SpokePositionReader.ReserveInfo[] memory reserves = reader.readSpokeReserves(address(spoke));

    assertEq(reserves.length, 3);
    assertEq(reserves[0].underlying, tokenA);
    assertEq(reserves[0].hub, hub);
    assertEq(reserves[0].hubAssetId, 4);
    assertEq(reserves[0].decimals, 18);
    assertFalse(reserves[0].paused);
    assertFalse(reserves[0].frozen);
    assertFalse(reserves[0].borrowable);
  }

  function testPositionUsesTheUserStoredDynamicConfigKey() public {
    spoke.setReserveDynamicConfigKey(0, 2);
    spoke.setDynamicReserveConfig(
      0,
      2,
      ISpoke.DynamicReserveConfig({
        collateralFactor: 8_500,
        maxLiquidationBonus: 11_000,
        liquidationFee: 500
      })
    );
    spoke.setDynamicReserveConfig(
      0,
      1,
      ISpoke.DynamicReserveConfig({
        collateralFactor: 7_500,
        maxLiquidationBonus: 12_000,
        liquidationFee: 400
      })
    );
    spoke.setUserPosition(
      0,
      user,
      ISpoke.UserPosition({
        drawnShares: 0,
        premiumShares: 0,
        premiumOffsetRay: 0,
        suppliedShares: 1,
        dynamicConfigKey: 1
      })
    );
    spoke.setUserReserve(0, user, 1 ether, 0, true, false);

    SpokePositionReader.ReserveInfo[] memory reserveCatalog = reader.readSpokeReserves(
      address(spoke)
    );
    SpokePositionReader.PositionSnapshot memory position = reader.readPosition(
      address(spoke), user
    );

    assertEq(reserveCatalog[0].dynamicConfigKey, 2);
    assertEq(reserveCatalog[0].collateralFactor, 8_500);
    assertEq(position.reserves.length, 1);
    assertEq(position.reserves[0].userDynamicConfigKey, 1);
    assertEq(position.reserves[0].userCollateralFactor, 7_500);
  }

  function testRejectsZeroSpoke() public {
    vm.expectRevert(SpokePositionReader.ZeroAddress.selector);
    reader.readPosition(address(0), user);
  }

  function testRejectsZeroUser() public {
    vm.expectRevert(SpokePositionReader.ZeroAddress.selector);
    reader.readPosition(address(spoke), address(0));
  }

  function testRejectsAddressWithoutCode() public {
    address eoa = makeAddr("not-a-contract");
    vm.expectRevert(abi.encodeWithSelector(SpokePositionReader.ContractHasNoCode.selector, eoa));
    reader.readPosition(eoa, user);
  }

  function testFuzzAccountDataIsPassedThroughWithoutRecalculation(
    uint128 healthFactor,
    uint128 collateralValue,
    uint128 debtValueRay
  ) public {
    ISpoke.UserAccountData memory expected = ISpoke.UserAccountData({
      riskPremium: 17,
      avgCollateralFactor: 8e17,
      healthFactor: uint256(healthFactor),
      totalCollateralValue: uint256(collateralValue),
      totalDebtValueRay: uint256(debtValueRay),
      activeCollateralCount: 2,
      borrowCount: 1
    });
    spoke.setUserAccountData(user, expected);

    SpokePositionReader.PositionSnapshot memory snapshot = reader.readPosition(
      address(spoke), user
    );
    assertEq(snapshot.accountData.healthFactor, expected.healthFactor);
    assertEq(snapshot.accountData.totalCollateralValue, expected.totalCollateralValue);
    assertEq(snapshot.accountData.totalDebtValueRay, expected.totalDebtValueRay);
  }
}
