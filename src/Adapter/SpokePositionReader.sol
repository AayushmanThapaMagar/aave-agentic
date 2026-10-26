// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {IHubBase} from "aave-v4/src/hub/interfaces/IHubBase.sol";
import {ISpoke} from "aave-v4/src/spoke/interfaces/ISpoke.sol";

/// @title SpokePositionReader
/// @notice Read-only discovery and position adapter for Aave V4 Hubs and Spokes.
/// @dev Uses Aave V4's native account-data calculation. It deliberately does not reimplement
///      health-factor, oracle, collateral-factor, premium-debt, or share-accounting math.
contract SpokePositionReader {
  error ZeroAddress();
  error ContractHasNoCode(address target);

  struct ReserveInfo {
    uint256 reserveId;
    address underlying;
    address hub;
    uint256 hubAssetId;
    uint8 decimals;
    uint24 collateralRisk;
    uint32 dynamicConfigKey;
    bool paused;
    bool frozen;
    bool borrowable;
    bool receiveSharesEnabled;
    uint16 collateralFactor;
    uint32 maxLiquidationBonus;
    uint16 liquidationFee;
  }

  struct ReservePosition {
    uint256 reserveId;
    address underlying;
    address hub;
    uint256 hubAssetId;
    uint8 decimals;
    uint256 suppliedAssets;
    uint256 borrowedAssets;
    bool collateralEnabled;
    bool borrowing;
    uint32 userDynamicConfigKey;
    uint16 userCollateralFactor;
  }

  struct HubAssetSnapshot {
    address hub;
    uint256 assetId;
    address underlying;
    uint8 decimals;
    uint256 availableLiquidity;
    uint256 totalOwed;
    uint256 totalAdded;
  }

  struct PositionSnapshot {
    uint256 chainId;
    uint256 blockNumber;
    uint256 blockTimestamp;
    address spoke;
    address user;
    ISpoke.UserAccountData accountData;
    ISpoke.LiquidationConfig liquidationConfig;
    ReservePosition[] reserves;
  }

  /// @notice Enumerates every reserve configured on a Spoke, including inactive reserves.
  /// @dev Dynamic reserve configuration is read at each reserve's current dynamicConfigKey.
  function readSpokeReserves(
    address spokeAddress
  ) external view returns (ReserveInfo[] memory result) {
    ISpoke spoke = _spokeAt(spokeAddress);
    uint256 reserveCount = spoke.getReserveCount();
    result = new ReserveInfo[](reserveCount);

    for (uint256 reserveId; reserveId < reserveCount; ++reserveId) {
      ISpoke.Reserve memory reserve = spoke.getReserve(reserveId);
      ISpoke.ReserveConfig memory config = spoke.getReserveConfig(reserveId);
      ISpoke.DynamicReserveConfig memory dynamicConfig = spoke.getDynamicReserveConfig(
        reserveId,
        reserve.dynamicConfigKey
      );

      result[reserveId] = ReserveInfo({
        reserveId: reserveId,
        underlying: reserve.underlying,
        hub: address(reserve.hub),
        hubAssetId: uint256(reserve.assetId),
        decimals: reserve.decimals,
        collateralRisk: reserve.collateralRisk,
        dynamicConfigKey: reserve.dynamicConfigKey,
        paused: config.paused,
        frozen: config.frozen,
        borrowable: config.borrowable,
        receiveSharesEnabled: config.receiveSharesEnabled,
        collateralFactor: dynamicConfig.collateralFactor,
        maxLiquidationBonus: dynamicConfig.maxLiquidationBonus,
        liquidationFee: dynamicConfig.liquidationFee
      });
    }
  }

  /// @notice Reads the Hub-side identity and accounting for one Hub asset.
  /// @dev Amounts are returned in the underlying token's raw units.
  function readHubAsset(
    address hubAddress,
    uint256 assetId
  ) external view returns (HubAssetSnapshot memory snapshot) {
    if (hubAddress == address(0)) revert ZeroAddress();
    if (hubAddress.code.length == 0) revert ContractHasNoCode(hubAddress);

    IHubBase hub = IHubBase(hubAddress);
    (address underlying, uint8 decimals) = hub.getAssetUnderlyingAndDecimals(assetId);

    snapshot = HubAssetSnapshot({
      hub: hubAddress,
      assetId: assetId,
      underlying: underlying,
      decimals: decimals,
      availableLiquidity: hub.getAssetLiquidity(assetId),
      totalOwed: hub.getAssetTotalOwed(assetId),
      totalAdded: hub.getAddedAssets(assetId)
    });
  }

  /// @notice Reads Spoke-level account data and every non-empty reserve position.
  /// @param spokeAddress A deployed Aave V4 Spoke address.
  /// @param user The account whose position is being read.
  /// @return snapshot A single-call snapshot of account data and active per-reserve balances.
  function readPosition(
    address spokeAddress,
    address user
  ) external view returns (PositionSnapshot memory snapshot) {
    if (user == address(0)) revert ZeroAddress();
    ISpoke spoke = _spokeAt(spokeAddress);
    uint256 reserveCount = spoke.getReserveCount();

    ReservePosition[] memory positions = new ReservePosition[](reserveCount);
    uint256 activeCount;

    for (uint256 reserveId; reserveId < reserveCount; ++reserveId) {
      ISpoke.Reserve memory reserve = spoke.getReserve(reserveId);
      (bool collateralEnabled, bool borrowing) = spoke.getUserReserveStatus(reserveId, user);
      uint256 suppliedAssets = spoke.getUserSuppliedAssets(reserveId, user);
      uint256 borrowedAssets = spoke.getUserTotalDebt(reserveId, user);

      // Include supplied-but-not-collateral reserves and any reserve whose status flag is set.
      if (suppliedAssets == 0 && borrowedAssets == 0 && !collateralEnabled && !borrowing) {
        continue;
      }

      ISpoke.UserPosition memory userPosition = spoke.getUserPosition(reserveId, user);
      ISpoke.DynamicReserveConfig memory userDynamicConfig = spoke.getDynamicReserveConfig(
        reserveId,
        userPosition.dynamicConfigKey
      );

      positions[activeCount] = ReservePosition({
        reserveId: reserveId,
        underlying: reserve.underlying,
        hub: address(reserve.hub),
        hubAssetId: uint256(reserve.assetId),
        decimals: reserve.decimals,
        suppliedAssets: suppliedAssets,
        borrowedAssets: borrowedAssets,
        collateralEnabled: collateralEnabled,
        borrowing: borrowing,
        userDynamicConfigKey: userPosition.dynamicConfigKey,
        userCollateralFactor: userDynamicConfig.collateralFactor
      });
      unchecked {
        ++activeCount;
      }
    }

    // Shrink the allocated array without another reserve scan.
    assembly ("memory-safe") {
      mstore(positions, activeCount)
    }

    snapshot = PositionSnapshot({
      chainId: block.chainid,
      blockNumber: block.number,
      blockTimestamp: block.timestamp,
      spoke: spokeAddress,
      user: user,
      accountData: spoke.getUserAccountData(user),
      liquidationConfig: spoke.getLiquidationConfig(),
      reserves: positions
    });
  }

  function _spokeAt(address spokeAddress) private view returns (ISpoke spoke) {
    if (spokeAddress == address(0)) revert ZeroAddress();
    if (spokeAddress.code.length == 0) revert ContractHasNoCode(spokeAddress);
    spoke = ISpoke(spokeAddress);
  }
}
