// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

struct NetworkConfig {
    address wethUsdPriceFeedAddress;
    address wbtcUsdPriceFeedAddress;
    address weth;
    address wbtc;
    uint256 deployerKey;
}

contract HelperConfig is Script {

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2_000e8;
    int256 public constant BTC_USD_PRICE = 50_000e8;
    uint256 public constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;

    constructor () {}

    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            // ETH / USD
            wethUsdPriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            // BTC / USD
            wbtcUsdPriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
    if (activeNetworkConfig.wethUsdPriceFeedAddress != address(0)) {
        return activeNetworkConfig;
    }

    vm.startBroadcast();
    MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
    ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);

    MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
    ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);
    vm.stopBroadcast();

    activeNetworkConfig = NetworkConfig({
        wethUsdPriceFeedAddress: address(ethUsdPriceFeed),
        wbtcUsdPriceFeedAddress: address(btcUsdPriceFeed),
        weth: address(wethMock),
        wbtc: address(wbtcMock),
        deployerKey: DEFAULT_ANVIL_KEY
        });

    return activeNetworkConfig;
    }
}
