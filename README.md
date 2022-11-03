# Overview

SIZE is a matching protocol that is designed to improve the efficiency of traders wanting to buy or sell large blocks of tokens.

SIZE's sealed bid auctions offer a superior auction experience for both buyers and sellers.

## Scope
All contracts under lib/ are not in scope

[**SizeSealed.sol (317 SLOC)**](https://github.com/code-423n4/2022-11-size/blob/main/src/SizeSealed.sol)

This is the main contract file that contains the auction creation, bidding and finalization logic. 

An auction can be created by providing the token addresses and amounts, the timing parameters (when the auction will start and end) and the vesting parameters (the emission schedule for the sold tokens). The seller also generates a random key-pair on the [alt_bn128 elliptic curve](https://eips.ethereum.org/EIPS/eip-197). The private key will be revealed at the end of the auction to ensure the integrity of the auction. 

Once an auction has been created, users can place an on-chain sealed bid by committing to a hidden number of base tokens for a given quote amount - sealing the price of the bid. The bidder encrypts the number of tokens to the seller's public key for future decryption.

Once an auction has finished, the seller has 24 hours to reveal the private key that corresponds to their public key. The auction is then finalized on-chain, filling the bidders that had the highest bid-price first until there are either no tokens or bidders left. All successful bidders get refunded the difference between their bid price and the lowest successful bid price. 

Tokens can be released immediately after finalization, or according to vesting parameters. 

[**ISizeSealed.sol (79 SLOC)**](https://github.com/code-423n4/2022-11-size/blob/main/src/interfaces/ISizeSealed.sol)

ISizeSealed is the interface file for the main sealed auction contract and includes the structs, events and errors used.

[**ECCMath.sol (41 SLOC)**](https://github.com/code-423n4/2022-11-size/blob/main/src/utils/ECCMath.sol)

ECCMath is a library that wraps the precompiled contract [ecMul at 0x07](https://www.evm.codes/precompiled#0x07?fork=grayGlacier) to implement asymmetric public key encryption on the [alt_bn128 elliptic curve](https://eips.ethereum.org/EIPS/eip-197). This is used by bidders to encrypt their bid prices to the seller's public key. They will be decrypted on-chain during the finalization process to ensure the auction has been settled fairly. 

[**CommonTokenMath.sol (48 SLOC)**](https://github.com/code-423n4/2022-11-size/blob/main/src/utils/CommonTokenMath.sol)

CommonTokenMath is a helper library used to calculate linear and cliff vesting schedules for the unlocking of tokens won in an auction.

## Areas of Interest

### SizeSealed
- Can a bid be filled below reserve price?
- Can a filled bid withdraw more base/quote tokens than it is owed?
- Can the price/time settlement priority in finalize() be bypassed?
- Can a bidder be filled at a price they didn't commit to?
- Can cancelling an auction or bid result in a loss-of-funds?
- Could a seller profit from manipulating their own auction i.e. by placing bids? 

### ECCMath
- Is there any information leakage in the encryption?
- Does the ecMul handle edge cases correctly?
- Could bad encryption result in a denial-of-service attack? 

### CommonTokenMath
- Is the vesting schedule followed during edge cases?
- Are there any rounding errors that result in a loss of funds?

## Build

SIZE is built using [Foundry](https://github.com/foundry-rs/foundry) - see the [installation guide](https://github.com/foundry-rs/foundry#installation) for how to install it.

Within the project directory, install dependencies:
```
forge install
```

To build the contracts:
```
forge build
```

## Tests

SIZE has written a suite of Foundry tests that include some fuzzed tests. 

To run the tests:

```
forge test
```

To report gas usage:

```
forge test --gas-report 
```
