// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {SizeSealed} from "../SizeSealed.sol";
import {MockBuyer} from "./mocks/MockBuyer.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockSeller} from "./mocks/MockSeller.sol";
import {ISizeSealed} from "../interfaces/ISizeSealed.sol";

contract SizeSealedFuzzTest is Test {
    SizeSealed auction;
    MockERC20 quoteToken;
    MockERC20 baseToken;

    MockSeller seller;
    MockBuyer bidder1;
    MockBuyer bidder2;
    MockBuyer bidder3;

    // Auction parameters (cliff unlock)
    uint32 auctionStart = uint32(block.timestamp);
    uint32 auctionEnd = auctionStart + 60;
    uint32 vestingStart = auctionEnd + 40;
    uint32 vestingEnd = vestingEnd + 900;

    uint128 baseToSell = 10 ether;
    uint128 minQuoteOffer = 1e6;

    uint128 bidderBaseDefault = 10 ether;
    uint128 bidderQuoteDefault = 10 ether;

    function setUp() public {
        // Create quote and bid tokens
        quoteToken = new MockERC20("USD Coin", "USDC", 6);
        baseToken = new MockERC20("ChainLink Token", "LINK", 18);

        // Init auction contract
        auction = new SizeSealed();

        // Create seller
        seller = new MockSeller(address(auction), quoteToken, baseToken);

        // Create bidders
        bidder1 = new MockBuyer(address(auction), quoteToken, baseToken);
        bidder2 = new MockBuyer(address(auction), quoteToken, baseToken);
        bidder3 = new MockBuyer(address(auction), quoteToken, baseToken);

        vm.label(address(bidder1), "Bidder 1");
        vm.label(address(bidder2), "Bidder 2");
        vm.label(address(bidder3), "Bidder 3");
        vm.label(address(quoteToken), "Quote Token");
        vm.label(address(baseToken), "Base Token");

        vm.warp(0);
    }

    function testWithdrawAmounts(
        uint128 b1BaseAmountBid,
        uint128 b1QuoteAmountBid,
        bytes16 b1salt,
        uint24 _startTime,
        uint24 endTimeOffset,
        uint24 vestingStartOffset,
        uint24 vestingEndOffset
    ) public {
        vm.assume(
            endTimeOffset > 0 && b1QuoteAmountBid > 0 && b1BaseAmountBid > 0 && b1QuoteAmountBid != type(uint128).max
                && b1BaseAmountBid != type(uint128).max
        );
        bidder1.mintQuote(b1QuoteAmountBid);

        (, uint256 sellerBaseBeforeCreate) = seller.balances();
        // Create an auction with the fuzzed timestamps
        uint256 aid = seller.createAuction(
            baseToSell,
            0,
            0,
            uint32(_startTime),
            uint32(_startTime) + uint32(endTimeOffset),
            uint32(_startTime) + uint32(vestingStartOffset) + uint32(endTimeOffset),
            uint32(_startTime) + uint32(vestingEndOffset) + uint32(vestingStartOffset) + uint32(endTimeOffset),
            0
        );
        // Ensure the baseTokens left the seller account
        (uint256 sellerQuoteAfterCreate, uint256 sellerBaseAfterCreate) = seller.balances();

        assertEq(sellerBaseBeforeCreate, sellerBaseAfterCreate + baseToSell, "seller baseToSell");

        bidder1.setAuctionId(aid);
        (uint256 b1QuoteBeforeBid,) = bidder1.balances();

        vm.warp(_startTime);
        // Bid on the created auction with the fuzzed bid amounts
        uint256 index = bidder1.bidOnAuctionWithSalt(b1BaseAmountBid, b1QuoteAmountBid, b1salt);

        // Ensure the tokens actually left the bidder account
        (uint256 b1QuoteAfterBid,) = bidder1.balances();
        assertEq(b1QuoteBeforeBid, b1QuoteAfterBid + b1QuoteAmountBid, "bidder1 quote balance before/after bidding");

        // Warp to the end of the auction bidding period and finalize the auction
        vm.warp(uint32(_startTime) + uint32(endTimeOffset) + 1);
        seller.finalize(createRevealedBids(index), b1BaseAmountBid, b1QuoteAmountBid);

        // Check the clearing price of the auction
        ISizeSealed.AuctionData memory data = auction.getAuctionData(aid);
        assertEq(data.lowestBase, b1BaseAmountBid, "data.lowestBase != b1BaseAmountBid");
        assertEq(data.lowestQuote, b1QuoteAmountBid, "data.lowestBase != b1BaseAmountBid");

        (uint256 sellerQuoteAfterFinalize, uint256 sellerBaseAfterFinalize) = seller.balances();

        // Calculate the seller's profit in quoteTokens
        // Need to account for bidding for more than the baseTokens available
        uint256 expectedSellerQuoteProfit = b1BaseAmountBid > baseToSell
            ? FixedPointMathLib.mulDivDown(b1QuoteAmountBid, baseToSell, b1BaseAmountBid)
            : b1QuoteAmountBid;
        assertEq(
            expectedSellerQuoteProfit,
            sellerQuoteAfterFinalize - sellerQuoteAfterCreate,
            "Seller Received incorrect quote amount from finalize()"
        );
        uint256 expectedSellerBaseRefund = b1BaseAmountBid >= baseToSell ? 0 : baseToSell - b1BaseAmountBid;
        assertEq(
            sellerBaseAfterCreate + expectedSellerBaseRefund,
            sellerBaseAfterFinalize,
            "Seller Received incorrect base refund from finalize()"
        );

        vm.warp(uint32(_startTime) + uint32(endTimeOffset) + uint32(vestingStartOffset) + uint32(vestingEndOffset / 2));
        (
            uint256 b1QuoteBeforeWithdraw,
            uint256 b1BaseBeforeWithdraw,
            uint256 b1QuoteAfterWithdraw,
            uint256 b1BaseAfterWithdraw
        ) = withdrawWithBalances(bidder1);

        // Calculate the buyer's deduction in quoteTokens
        // Accounting for refunds & (halfway thru vesting)
        uint128 expectedBuyerBaseAmount = b1BaseAmountBid > baseToSell ? baseToSell : b1BaseAmountBid;
        uint128 expectedBuyerBaseWithdrawn = auction.tokensAvailableForWithdrawal(aid, expectedBuyerBaseAmount);
        assertEq(
            expectedBuyerBaseWithdrawn,
            b1BaseAfterWithdraw - b1BaseBeforeWithdraw,
            "bidder1 Received incorrect base amount from finalize()"
        );
        uint256 expectedBuyerQuoteRefund = b1BaseAmountBid > baseToSell
            ? b1QuoteAmountBid - FixedPointMathLib.mulDivDown(b1QuoteAmountBid, baseToSell, b1BaseAmountBid)
            : 0;
        assertEq(
            expectedBuyerQuoteRefund,
            b1QuoteAfterWithdraw - b1QuoteBeforeWithdraw,
            "bidder1 Received incorrect quote refund from withdraw()"
        );
    }

    function testTokensAvailableForWithdrawal(
        uint24 _startTime,
        uint24 endTimeOffset,
        uint24 vestingStartOffset,
        uint24 vestingEndOffset
    ) public {
        vm.assume(endTimeOffset > 0 && vestingEndOffset % 4 == 0 && vestingEndOffset > 0);
        teleportThroughAuctionFinalize(_startTime, endTimeOffset, vestingStartOffset, vestingEndOffset);

        vestingStart = uint32(_startTime) + uint32(endTimeOffset) + uint32(vestingStartOffset);

        vm.warp(vestingStart);
        uint256 expectedBase = 0;
        (, uint256 baseBefore,, uint256 baseAfter) = withdrawWithBalances(bidder1);
        assertEq(baseBefore, baseAfter + expectedBase, "bidder should not get tokens at t=0");

        vm.warp(vestingStart + uint32(vestingEndOffset) / 4);
        expectedBase = bidderBaseDefault / 4;
        (, baseBefore,, baseAfter) = withdrawWithBalances(bidder1);
        assertEq(baseBefore + expectedBase, baseAfter, "bidder tokens at t=25%");

        vm.warp(vestingStart + uint32(vestingEndOffset) / 2);
        expectedBase = bidderBaseDefault / 2;
        (,,, baseAfter) = withdrawWithBalances(bidder1);
        assertEq(baseBefore + expectedBase, baseAfter, "bidder tokens at t=50%");

        vm.warp(vestingStart + uint32(vestingEndOffset) * 3 / 4);
        expectedBase = bidderBaseDefault * 3 / 4;
        (,,, baseAfter) = withdrawWithBalances(bidder1);
        assertEq(baseBefore + expectedBase, baseAfter, "bidder tokens at t=75%");

        vm.warp(vestingStart + uint32(vestingEndOffset) + 1);
        (,,, baseAfter) = withdrawWithBalances(bidder1);
        assertEq(baseBefore + bidderBaseDefault, baseAfter, "bidder tokens at t=end+1");
    }

    // Helper Functions

    function withdrawWithBalances(MockBuyer bidder)
        internal
        returns (uint256 quoteBefore, uint256 baseBefore, uint256 quoteAfter, uint256 baseAfter)
    {
        (quoteBefore, baseBefore) = bidder.balances();
        bidder.withdraw();
        (quoteAfter, baseAfter) = bidder.balances();
    }

    function teleportThroughAuctionFinalize(
        uint32 _startTime,
        uint32 endTimeOffset,
        uint32 vestingStartOffset,
        uint32 vestingEndOffset
    ) internal {
        uint256 aid = seller.createAuction(
            baseToSell,
            0,
            0,
            _startTime,
            _startTime + endTimeOffset,
            _startTime + vestingStartOffset + endTimeOffset,
            _startTime + vestingEndOffset + vestingStartOffset + endTimeOffset,
            0
        );
        bidder1.setAuctionId(aid);
        vm.warp(_startTime);
        uint256 index = bidder1.bidOnAuctionWithSalt(bidderBaseDefault, bidderQuoteDefault, "");
        vm.warp(uint32(_startTime) + uint32(endTimeOffset) + 1);
        seller.finalize(createRevealedBids(index), bidderBaseDefault, bidderQuoteDefault);
    }

    function createRevealedBids(uint256 bidIndex) internal pure returns (uint256[] memory bidIndices) {
        bidIndices = new uint[](1);
        bidIndices[0] = bidIndex;
    }
}
