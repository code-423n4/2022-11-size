// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {DSTest} from "ds-test/test.sol";

import {MockERC20} from "./MockERC20.sol";
import {ECCMath} from "../../util/ECCMath.sol";
import {SizeSealed} from "../../SizeSealed.sol";
import {ISizeSealed} from "../../interfaces/ISizeSealed.sol";

contract MockSeller is ISizeSealed, DSTest {
    SizeSealed auctionContract;

    uint256 auctionId;
    ECCMath.Point publicKey;

    MockERC20 quoteToken;
    MockERC20 baseToken;

    uint256 constant SELLER_PRIVATE_KEY = uint256(keccak256("Size Seller"));
    uint256 constant SELLER_STARTING_BASE = 100 ether;

    constructor(address _auction_contract, MockERC20 _quoteToken, MockERC20 _baseToken) {
        auctionContract = SizeSealed(_auction_contract);
        quoteToken = _quoteToken;
        baseToken = _baseToken;
        publicKey = ECCMath.publicKey(SELLER_PRIVATE_KEY);
        mintBase(SELLER_STARTING_BASE);
    }

    function createAuction(
        uint128 totalBaseTokens,
        uint256 reserveQuotePerBase,
        uint128 minimumBidQuote,
        uint32 startTimestamp,
        uint32 endTimestamp,
        uint32 unlockStartTimestamp,
        uint32 unlockEndTimestamp,
        uint128 cliffPercent
    ) public returns (uint256) {
        ISizeSealed.Timings memory timings = ISizeSealed.Timings(
            uint32(startTimestamp),
            uint32(endTimestamp),
            uint32(unlockStartTimestamp),
            uint32(unlockEndTimestamp),
            uint128(cliffPercent)
        );

        ISizeSealed.AuctionParameters memory params = ISizeSealed.AuctionParameters(
            address(baseToken),
            address(quoteToken),
            reserveQuotePerBase,
            totalBaseTokens,
            minimumBidQuote,
            bytes32(0),
            publicKey
        );

        auctionId = auctionContract.createAuction(params, timings, "");
        return auctionId;
    }

    function createAuctionWhitelist(
        uint128 totalBaseTokens,
        uint256 reserveQuotePerBase,
        uint128 minimumBidQuote,
        uint32 startTimestamp,
        uint32 endTimestamp,
        uint32 unlockStartTimestamp,
        uint32 unlockEndTimestamp,
        uint128 cliffPercent,
        bytes32 merkleRoot
    ) public returns (uint256) {
        ISizeSealed.Timings memory timings = ISizeSealed.Timings(
            uint32(startTimestamp),
            uint32(endTimestamp),
            uint32(unlockStartTimestamp),
            uint32(unlockEndTimestamp),
            uint128(cliffPercent)
        );

        ISizeSealed.AuctionParameters memory params = ISizeSealed.AuctionParameters(
            address(baseToken),
            address(quoteToken),
            reserveQuotePerBase,
            totalBaseTokens,
            minimumBidQuote,
            merkleRoot,
            publicKey
        );

        auctionId = auctionContract.createAuction(params, timings, "");
        return auctionId;
    }

    function finalize(uint256[] calldata bidIndices, uint128 clearingBase, uint128 clearingQuote) public {
        auctionContract.reveal(auctionId, SELLER_PRIVATE_KEY, abi.encode(bidIndices, clearingBase, clearingQuote));
        // auctionContract.finalize(auctionId, bidIndices, clearingBase, clearingQuote);
    }

    function cancelAuction() public {
        auctionContract.cancelAuction(auctionId);
    }

    function balances() public view returns (uint256, uint256) {
        return (quoteToken.balanceOf(address(this)), baseToken.balanceOf(address(this)));
    }

    function mintBase(uint256 amount) public {
        baseToken.mint(address(this), amount);
        baseToken.approve(address(auctionContract), type(uint256).max);
    }
}
