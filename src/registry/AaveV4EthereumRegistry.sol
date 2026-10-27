// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

/// @title AaveV4EthereumRegistry
/// @notice Ethereum mainnet V4 deployment addresses sourced from the Aave DAO address book.
/// @dev Refresh this registry from a pinned aave-address-book revision before each release.
library AaveV4EthereumRegistry {
  uint256 internal constant CHAIN_ID = 1;

  address internal constant CORE_HUB = 0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9;
  address internal constant PLUS_HUB = 0x06002e9c4412CB7814a791eA3666D905871E536A;
  address internal constant PRIME_HUB = 0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931;
  address internal constant GLOBAL_DOLLAR_HUB = 0x62d63197660c080236193CA60b70E49A08E90368;

  // Canonical Main Spoke selected for the first read-only integration milestone.
  address internal constant MAIN_SPOKE = 0x94e7A5dCbE816e498b89aB752661904E2F56c485;

  error UnsupportedChain(uint256 actualChainId);

  struct NamedAddress {
    string name;
    address addr;
  }

  function requireEthereumMainnet() internal view {
    if (block.chainid != CHAIN_ID) revert UnsupportedChain(block.chainid);
  }

  function hubs() internal pure returns (NamedAddress[] memory result) {
    result = new NamedAddress[](4);
    result[0] = NamedAddress({name: "Core", addr: CORE_HUB});
    result[1] = NamedAddress({name: "Plus", addr: PLUS_HUB});
    result[2] = NamedAddress({name: "Prime", addr: PRIME_HUB});
    result[3] = NamedAddress({name: "Global Dollar", addr: GLOBAL_DOLLAR_HUB});
  }

  /// @notice Returns the 13 standard Spokes in AaveV4EthereumGetters.getAllSpokes().
  /// @dev The separate Treasury Spoke is intentionally omitted: it is exposed as ITreasurySpoke
  ///      rather than one of the 13 standard ISpoke entries in the address-book getter.
  function spokes() internal pure returns (NamedAddress[] memory result) {
    result = new NamedAddress[](13);
    result[0] = NamedAddress({name: "Bluechip", addr: 0x973a023A77420ba610f06b3858aD991Df6d85A08});
    result[1] = NamedAddress({
      name: "Ethena Correlated",
      addr: 0x58131E79531caB1d52301228d1f7b842F26B9649
    });
    result[2] = NamedAddress({
      name: "Ethena Ecosystem",
      addr: 0xba1B3D55D249692b669A164024A838309B7508AF
    });
    result[3] = NamedAddress({name: "Forex", addr: 0xD8B93635b8C6d0fF98CbE90b5988E3F2d1Cd9da1});
    result[4] = NamedAddress({name: "Gold", addr: 0x65407b940966954b23dfA3caA5C0702bB42984DC});
    result[5] = NamedAddress({
      name: "Lombard BTC",
      addr: 0x7EC68b5695e803e98a21a9A05d744F28b0a7753D
    });
    result[6] = NamedAddress({name: "Main", addr: MAIN_SPOKE});
    result[7] = NamedAddress({name: "PAXG Gold", addr: 0xAD75cE6354f87F3135cE10621d385d8D1e2562C2});
    result[8] = NamedAddress({
      name: "USDG Pendle",
      addr: 0x956d8e0A89cfa3744428C4641b5a53B56167a7f9
    });
    result[9] = NamedAddress({
      name: "EtherFi eSpoke",
      addr: 0xbF10BDfE177dE0336aFD7fcCF80A904E15386219
    });
    result[10] = NamedAddress({
      name: "Kelp eSpoke",
      addr: 0x3131FE68C4722e726fe6B2819ED68e514395B9a4
    });
    result[11] = NamedAddress({
      name: "Lido eSpoke",
      addr: 0xe1900480ac69f0B296841Cd01cC37546d92F35Cd
    });
    result[12] = NamedAddress({
      name: "USDG Maple eSpoke",
      addr: 0x774b9655413c34809c1f1b16b654465A89EBE989
    });
  }
}
