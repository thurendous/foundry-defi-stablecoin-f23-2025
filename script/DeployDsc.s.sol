// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {HelperConfig, NetworkConfig} from "./HelperConfig.s.sol";

contract DeployDscScript is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DSCEngine, DecentralizedStableCoin, HelperConfig) {
      HelperConfig helperConfig = new HelperConfig();
      NetworkConfig memory anvilConfig = helperConfig.getOrCreateAnvilEthConfig();
      vm.startBroadcast(anvilConfig.deployerKey);

      tokenAddresses = [anvilConfig.weth, anvilConfig.wbtc];
      priceFeedAddresses = [anvilConfig.wethUsdPriceFeedAddress, anvilConfig.wbtcUsdPriceFeedAddress];

      DecentralizedStableCoin dsc = new DecentralizedStableCoin();
      DSCEngine engine = new DSCEngine(address(dsc), tokenAddresses, priceFeedAddresses);
      dsc.transferOwnership(address(engine));

      vm.stopBroadcast();

      return (engine, dsc, helperConfig);
    }
}

