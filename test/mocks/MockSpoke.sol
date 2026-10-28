// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ISpoke, ReserveFlags} from "aave-v4/src/spoke/interfaces/ISpoke.sol";
import {IHubBase} from "aave-v4/src/hub/interfaces/IHubBase.sol";

/// @dev ABI-compatible test double implementing only the ISpoke selectors used by the reader.
contract MockSpoke {
  ISpoke.Reserve[] private _reserves;

  mapping(uint256 => ISpoke.ReserveConfig) private _reserveConfigs;
  mapping(uint256 => mapping(uint32 => ISpoke.DynamicReserveConfig)) private _dynamicConfigs;
  mapping(uint256 => mapping(address => ISpoke.UserPosition)) private _userPositions;
  mapping(uint256 => mapping(address => uint256)) private _supplied;
  mapping(uint256 => mapping(address => uint256)) private _borrowed;
  mapping(uint256 => mapping(address => bool)) private _collateral;
  mapping(uint256 => mapping(address => bool)) private _borrowing;
  mapping(address => ISpoke.UserAccountData) private _accountData;
  ISpoke.LiquidationConfig private _liquidationConfig;

  function addReserve(
    address underlying,
    address hub,
    uint16 assetId,
    uint8 decimals
  ) external returns (uint256 reserveId) {
    reserveId = _reserves.length;
    _reserves.push(
      ISpoke.Reserve({
        underlying: underlying,
        hub: IHubBase(hub),
        assetId: assetId,
        decimals: decimals,
        collateralRisk: 0,
        flags: ReserveFlags.wrap(0),
        dynamicConfigKey: 0
      })
    );
  }

  function setReserveDynamicConfigKey(uint256 reserveId, uint32 key) external {
    _reserves[reserveId].dynamicConfigKey = key;
  }

  function setReserveConfig(uint256 reserveId, ISpoke.ReserveConfig calldata config) external {
    _reserveConfigs[reserveId] = config;
  }

  function setDynamicReserveConfig(
    uint256 reserveId,
    uint32 key,
    ISpoke.DynamicReserveConfig calldata config
  ) external {
    _dynamicConfigs[reserveId][key] = config;
  }

  function setUserPosition(
    uint256 reserveId,
    address user,
    ISpoke.UserPosition calldata position
  ) external {
    _userPositions[reserveId][user] = position;
  }

  function setUserReserve(
    uint256 reserveId,
    address user,
    uint256 suppliedAssets,
    uint256 borrowedAssets,
    bool collateralEnabled,
    bool borrowing
  ) external {
    _supplied[reserveId][user] = suppliedAssets;
    _borrowed[reserveId][user] = borrowedAssets;
    _collateral[reserveId][user] = collateralEnabled;
    _borrowing[reserveId][user] = borrowing;
  }

  function setUserAccountData(
    address user,
    ISpoke.UserAccountData calldata data
  ) external {
    _accountData[user] = data;
  }

  function setLiquidationConfig(ISpoke.LiquidationConfig calldata config) external {
    _liquidationConfig = config;
  }

  function getReserveCount() external view returns (uint256) {
    return _reserves.length;
  }

  function getReserve(uint256 reserveId) external view returns (ISpoke.Reserve memory) {
    return _reserves[reserveId];
  }

  function getReserveConfig(uint256 reserveId) external view returns (ISpoke.ReserveConfig memory) {
    return _reserveConfigs[reserveId];
  }

  function getDynamicReserveConfig(
    uint256 reserveId,
    uint32 key
  ) external view returns (ISpoke.DynamicReserveConfig memory) {
    return _dynamicConfigs[reserveId][key];
  }

  function getUserReserveStatus(
    uint256 reserveId,
    address user
  ) external view returns (bool, bool) {
    return (_collateral[reserveId][user], _borrowing[reserveId][user]);
  }

  function getUserSuppliedAssets(uint256 reserveId, address user) external view returns (uint256) {
    return _supplied[reserveId][user];
  }

  function getUserTotalDebt(uint256 reserveId, address user) external view returns (uint256) {
    return _borrowed[reserveId][user];
  }

  function getUserPosition(
    uint256 reserveId,
    address user
  ) external view returns (ISpoke.UserPosition memory) {
    return _userPositions[reserveId][user];
  }

  function getUserAccountData(
    address user
  ) external view returns (ISpoke.UserAccountData memory) {
    return _accountData[user];
  }

  function getLiquidationConfig() external view returns (ISpoke.LiquidationConfig memory) {
    return _liquidationConfig;
  }
}
