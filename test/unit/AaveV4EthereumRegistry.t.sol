// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AaveV4EthereumRegistry} from "aave-position-guardian/registry/AaveV4EthereumRegistry.sol";

contract AaveV4EthereumRegistryTest is Test {
  function testRegistryHasFourHubsAndThirteenStandardSpokes() public {
    AaveV4EthereumRegistry.NamedAddress[] memory hubs = AaveV4EthereumRegistry.hubs();
    AaveV4EthereumRegistry.NamedAddress[] memory spokes = AaveV4EthereumRegistry.spokes();

    assertEq(hubs.length, 4);
    assertEq(spokes.length, 13);
    assertEq(AaveV4EthereumRegistry.MAIN_SPOKE, spokes[6].addr);
    assertEq(spokes[6].name, "Main");
  }

  function testRequireEthereumMainnetAcceptsChainOne() public {
    vm.chainId(1);
    AaveV4EthereumRegistry.requireEthereumMainnet();
  }

  function testRequireEthereumMainnetRejectsOtherChains() public {
    vm.chainId(8453);
    vm.expectRevert(
      abi.encodeWithSelector(AaveV4EthereumRegistry.UnsupportedChain.selector, 8453)
    );
    AaveV4EthereumRegistry.requireEthereumMainnet();
  }

  function testKnownHubAddresses() public {
    AaveV4EthereumRegistry.NamedAddress[] memory hubs = AaveV4EthereumRegistry.hubs();
    assertEq(hubs[0].addr, 0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9);
    assertEq(hubs[1].addr, 0x06002e9c4412CB7814a791eA3666D905871E536A);
    assertEq(hubs[2].addr, 0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931);
    assertEq(hubs[3].addr, 0x62d63197660c080236193CA60b70E49A08E90368);
  }
}
