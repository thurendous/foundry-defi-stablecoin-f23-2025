# Stable coin protocol 

1. (Relative Stability) Anchored or Pegged -> $1.00
   1. Chainlink Price Feed.
   2. Set a function to exchange ETH & BTC to $USD.
2. Stability Mechanism (Minting): Algorithmic (Decentralized)
   1. People can only mint the stablecoin with enough collateral. (coded)
3. Collateral: Exogenous (Crypto) ->这意味着，这个稳定币的抵押物是外部依赖的
   1. wETH
   2. wBTC
      1. This is a wrapper token for BTC which can be a little bit centralized.
4. 



1. What are our invariants/properties?
   1. The system should always be overcollateralized.
   2. The system should always be solvent.
   3. The system should always be liquid.

## Invariant testing

1. If you want to test the invariant, you need to do this: 
   - import the invariant testing library.
   - create a function starts with `invariant_`.
   - use `assert` to check the invariant.
By doing this, the fuzzer will call any of the contract's function and then check the invariant.


## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
