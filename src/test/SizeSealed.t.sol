// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {Merkle} from "murky/Merkle.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {ECCMath} from "../util/ECCMath.sol";
import {SizeSealed} from "../SizeSealed.sol";
import {MockBuyer} from "./mocks/MockBuyer.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockSeller} from "./mocks/MockSeller.sol";
import {ISizeSealed} from "../interfaces/ISizeSealed.sol";

contract SizeSealedTest is Test, ISizeSealed {

    SizeSealed auction;

    MockSeller seller;
    MockERC20 quoteToken;
    MockERC20 baseToken;

    MockBuyer bidder1;
    MockBuyer bidder2;
    MockBuyer bidder3;

    // Auction parameters (cliff unlock)
    uint32 startTime;
    uint32 endTime;
    uint32 unlockTime;
    uint32 unlockEnd;
    uint128 cliffPercent;

    uint128 baseToSell;

    uint256 reserveQuotePerBase = 0.5e6 * uint256(type(uint128).max) / 1e18;
    uint128 minimumBidQuote = 1e6;

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

        startTime = uint32(block.timestamp);
        endTime = uint32(block.timestamp) + 60;
        unlockTime = uint32(block.timestamp) + 100;
        unlockEnd = uint32(block.timestamp) + 1000;
        cliffPercent = 0;

        baseToSell = 10 ether;

        vm.label(address(bidder1), "Bidder 1");
        vm.label(address(bidder2), "Bidder 2");
        vm.label(address(bidder3), "Bidder 3");
        vm.label(address(quoteToken), "Quote Token");
        vm.label(address(baseToken), "Base Token");
    }

    // Test against vitalik's ecmul bn_128 impl
    // https://github.com/ethereum/py_pairing/blob/master/tests/test_bn128.py
    function testECMUL() public {
        ECCMath.Point memory pubKey = ECCMath.publicKey(1);
        assertEq(pubKey.x, 1);
        assertEq(pubKey.y, 2);

        // Not on curve
        pubKey = ECCMath.publicKey(0);
        assertEq(pubKey.x, 1);
        assertEq(pubKey.y, 1);

        pubKey = ECCMath.publicKey(10);
        assertEq(pubKey.x, 4444740815889402603535294170722302758225367627362056425101568584910268024244);
        assertEq(pubKey.y, 10537263096529483164618820017164668921386457028564663708352735080900270541420);

        pubKey = ECCMath.publicKey(100);
        assertEq(pubKey.x, 8464813805670834410435113564993955236359239915934467825032129101731355555480);
        assertEq(pubKey.y, 15805858227829959406383193382434604346463310251314385567227770510519895659279);

        pubKey = ECCMath.publicKey(1000);
        assertEq(pubKey.x, 1877430218621023249938287835150142829605985124239973405386905603937246406682);
        assertEq(pubKey.y, 5158670745399576371417749445914270010222487318683077220882364692777539249273);
    }

    function testCreateAuction() public {
        seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
    }

    function testCancelAuction() public {
        (uint256 beforeQuote, uint256 beforeBase) = seller.balances();
        seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        seller.cancelAuction();
        (uint256 afterQuote, uint256 afterBase) = seller.balances();
        assertEq(beforeBase, afterBase, "base before cancel != base after cancel");
        assertEq(beforeQuote, afterQuote, "quote before cancel != quote after cancel");
    }

    function testCancelAuctionDuringRevealPeriod() public {
        seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        vm.warp(endTime);
        seller.cancelAuction();
    }

    function testCreateAuctionTimings() public {
        // End in the past
        vm.expectRevert(ISizeSealed.InvalidTimestamp.selector);
        seller.createAuction(
            baseToSell,
            reserveQuotePerBase,
            minimumBidQuote,
            startTime,
            uint32(block.timestamp - 1),
            unlockTime,
            unlockEnd,
            cliffPercent
        );

        // End before start
        vm.expectRevert(ISizeSealed.InvalidTimestamp.selector);
        seller.createAuction(
            baseToSell,
            reserveQuotePerBase,
            minimumBidQuote,
            startTime + 2,
            startTime + 2,
            unlockTime,
            unlockEnd,
            cliffPercent
        );

        // Vesting starts before end
        vm.expectRevert(ISizeSealed.InvalidTimestamp.selector);
        seller.createAuction(
            baseToSell,
            reserveQuotePerBase,
            minimumBidQuote,
            startTime,
            unlockTime + 1,
            unlockTime,
            unlockEnd,
            cliffPercent
        );

        // Vesting ends before vesting starts
        vm.expectRevert(ISizeSealed.InvalidTimestamp.selector);
        seller.createAuction(
            baseToSell,
            reserveQuotePerBase,
            minimumBidQuote,
            startTime,
            endTime,
            unlockTime,
            unlockTime - 1,
            cliffPercent
        );
    }

    function testCreateAuctionReserve() public {
        // Min bid is more than reserve
        uint256 reserve = 10e6 * uint256(type(uint128).max) / baseToSell;
        uint128 minBid = 10e6 + 1;
        vm.expectRevert(ISizeSealed.InvalidReserve.selector);
        seller.createAuction(baseToSell, reserve, minBid, startTime, endTime, unlockTime, unlockEnd, cliffPercent);
    }

    function testCancelAuctionAfterFinalization() public {
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        bidder1.bidOnAuctionWithSalt(1 ether, 10 ether, "hello");

        uint256[] memory bidIndices = new uint[](1);
        bidIndices[0] = 0;

        vm.warp(endTime);
        seller.finalize(bidIndices, 1 ether, 10 ether);
        // Cancel should fail
        vm.expectRevert(ISizeSealed.InvalidState.selector);
        seller.cancelAuction();
    }

    function testAuctionFinalizeBeforeReveal() public {
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        bidder1.bidOnAuctionWithSalt(1 ether, 10 ether, "hello");

        uint256[] memory bidIndices = new uint[](1);
        bidIndices[0] = 0;

        vm.warp(endTime);
        vm.prank(address(seller));
        vm.expectRevert(ISizeSealed.InvalidPrivateKey.selector);
        auction.finalize(aid, bidIndices, 1 ether, 10 ether);
    }

    /*
    Test with a single bidder
    Base amoount = 1 ether, quote amount = 10 ether
    Price = 10 q per b
    */
    function testSingleBid() public {
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        (uint256 beforeQuote, uint256 beforeBase) = bidder1.balances();
        bidder1.bidOnAuction(1 ether, 10e6);
        (uint256 afterQuote, uint256 afterBase) = bidder1.balances();
        assertEq(beforeQuote, afterQuote + 10e6);
        assertEq(beforeBase, afterBase);
    }

    function testMultipleBids() public {
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        bidder2.setAuctionId(aid);
        (uint256 beforeQuote, uint256 beforeBase) = bidder1.balances();
        (uint256 beforeQuote2, uint256 beforeBase2) = bidder2.balances();
        bidder1.bidOnAuction(1 ether, 10e6);
        bidder2.bidOnAuction(1 ether, 8e6);
        (uint256 afterQuote, uint256 afterBase) = bidder1.balances();
        (uint256 afterQuote2, uint256 afterBase2) = bidder2.balances();
        assertEq(beforeQuote, afterQuote + 10e6);
        assertEq(beforeBase, afterBase);

        assertEq(beforeQuote2, afterQuote2 + 8e6);
        assertEq(beforeBase2, afterBase2);
    }

    function testFailSingleBidBeforeAuctionStart() public {
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        vm.warp(startTime - 1);
        bidder1.bidOnAuction(1 ether, 10e6);
    }

    function testBidBelowMin() public {
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        vm.expectRevert(ISizeSealed.InvalidBidAmount.selector);
        bidder1.bidOnAuction(1 ether, 0.8e6);
    }

    function cancelSetup() internal {
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        bidder1.bidOnAuctionWithSalt(1 ether, 10e6, "hello");
    }

    function testCancelBidAfterFinalize() public {
        cancelSetup();
        uint256[] memory bidIndices = new uint[](1);
        bidIndices[0] = 0;
        vm.warp(endTime);
        seller.finalize(bidIndices, 1 ether, 10e6);
        
        vm.expectRevert(ISizeSealed.InvalidState.selector);
        bidder1.cancel();
        
        vm.warp(endTime + 25 hours);
        vm.expectRevert(ISizeSealed.InvalidState.selector);
        bidder1.cancel();
    }

    function testCancelBidDuringRevealBeforeFinalize() public {
        cancelSetup();
        vm.warp(endTime + 1);
        vm.expectRevert(ISizeSealed.InvalidState.selector);
        bidder1.cancel();
    }

    function testCancelBidDuringVoidedNoFinalize() public {
        cancelSetup();
        vm.warp(endTime + 25 hours);
        bidder1.cancel();
    }

    function testCancelSingleBid() public {
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        (uint256 beforeQuote, uint256 beforeBase) = bidder1.balances();
        bidder1.bidOnAuction(1 ether, 10e6);
        (uint256 afterQuote, uint256 afterBase) = bidder1.balances();
        assertEq(beforeQuote, afterQuote + 10e6);
        // Test cancel while auction is still running
        bidder1.cancel();
        (uint256 cancelQuote, uint256 cancelBase) = bidder1.balances();
        assertEq(cancelQuote, beforeQuote);
        assertEq(beforeBase, afterBase);
        assertEq(beforeBase, cancelBase);
    }

    function testAuctionFinaliseEarly() public {
        seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        uint256[] memory bidIndices = new uint[](2);
        vm.expectRevert(ISizeSealed.InvalidState.selector);
        seller.finalize(bidIndices, 0, 0);
    }

    function testAuctionFinalizePriceSort() public {
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        bidder2.setAuctionId(aid);
        bidder1.bidOnAuctionWithSalt(1 ether, 11e6, "hello");
        bidder2.bidOnAuctionWithSalt(1 ether, 10e6, "hello2");

        uint256[] memory bidIndices = new uint[](2);
        bidIndices[0] = 1;
        bidIndices[1] = 0;

        vm.warp(endTime);
        vm.expectRevert(ISizeSealed.InvalidSorting.selector);
        seller.finalize(bidIndices, 1 ether, 10e6);
    }

    function testAuctionFinalizeTimeSort() public {
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        bidder2.setAuctionId(aid);
        bidder1.bidOnAuctionWithSalt(1 ether, 10e6, "hello");
        bidder2.bidOnAuctionWithSalt(1 ether, 10e6, "hello2");

        uint256[] memory bidIndices = new uint[](2);
        bidIndices[0] = 1;
        bidIndices[1] = 0;

        vm.warp(endTime);
        vm.expectRevert(ISizeSealed.InvalidSorting.selector);
        seller.finalize(bidIndices, 1 ether, 10e6);
    }

    function testFinalizeAfterVoided() public {
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        bidder2.setAuctionId(aid);
        bidder1.bidOnAuctionWithSalt(1 ether, 10e6, "hello");
        bidder2.bidOnAuctionWithSalt(1 ether, 11e6, "hello2");

        uint256[] memory bidIndices = new uint[](2);
        bidIndices[0] = 1;
        bidIndices[1] = 0;

        vm.warp(endTime + 24 hours + 1);
        vm.expectRevert(ISizeSealed.InvalidState.selector);
        seller.finalize(bidIndices, 1 ether, 10e6);
    }

    function testAuctionFinalizePartial() public {
        (uint256 sellerQuoteBeforeFinalize, uint256 sellerBaseBeforeFinalize) = seller.balances();
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        bidder2.setAuctionId(aid);
        (uint256 b1QuoteBeforeFinalize,) = bidder1.balances();
        (uint256 b2QuoteBeforeFinalize,) = bidder2.balances();
        bidder1.bidOnAuctionWithSalt(9 ether, 4.5e6, "hello");
        bidder2.bidOnAuctionWithSalt(2 ether, 2e6, "hello2");
        uint256[] memory bidIndices = new uint[](2);
        bidIndices[0] = 1;
        bidIndices[1] = 0;
        vm.warp(endTime + 1);

        seller.finalize(bidIndices, 9 ether, 4.5e6);

        (uint256 sellerQuoteAfterFinalize, uint256 sellerBaseAfterFinalize) = seller.balances();
        (uint256 b1QuoteAfterFinalize, uint256 b1BaseAfterFinalize) = bidder1.balances();
        (uint256 b2QuoteAfterFinalize, uint256 b2BaseAfterFinalize) = bidder2.balances();

        assertEq(sellerQuoteBeforeFinalize, sellerQuoteAfterFinalize - 5e6, "quote gain for seller");
        assertEq(sellerBaseBeforeFinalize - 10 ether, sellerBaseAfterFinalize, "base sold for seller");

        assertEq(b1QuoteBeforeFinalize - 4.5e6, b1QuoteAfterFinalize, "quote gain for buyer");
        assertEq(b2QuoteBeforeFinalize - 2e6, b2QuoteAfterFinalize, "quote gain for buyer");

        vm.warp(unlockEnd + 1);
        bidder1.withdraw();
        bidder2.withdraw();

        (uint256 b1QuoteAfterWithdraw, uint256 b1BaseAfterWithdraw) = bidder1.balances();
        (uint256 b2QuoteAfterWithdraw, uint256 b2BaseAfterWithdraw) = bidder2.balances();

        assertEq(b1QuoteAfterFinalize + 0.5e6, b1QuoteAfterWithdraw, "B1 Incorrect Refund");
        assertEq(b1BaseAfterFinalize + 8 ether, b1BaseAfterWithdraw, "B1 Incorrect Base Withdraw");
        assertEq(b2QuoteAfterFinalize + 1e6, b2QuoteAfterWithdraw, "B2 Incorrect Refund");
        assertEq(b2BaseAfterFinalize + 2 ether, b2BaseAfterWithdraw, "B2 Incorrect Base Withdraw");
    }

    function testAuctionOneBidFinalise() public {
        (uint256 sellerBeforeQuote, uint256 sellerBeforeBase) = seller.balances();
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        (uint256 buyerBeforeQuote,) = bidder1.balances();
        bidder1.bidOnAuctionWithSalt(1 ether, 5e6, "hello");
        uint256[] memory bidIndices = new uint[](1);
        bidIndices[0] = 0;
        vm.warp(endTime + 1);
        seller.finalize(bidIndices, 1 ether, 5e6);
        (uint256 sellerAfterQuote, uint256 sellerAfterBase) = seller.balances();
        (uint256 buyerAfterQuote,) = bidder1.balances();
        assertEq(sellerBeforeQuote, sellerAfterQuote - 5e6, "quote gain for seller");
        assertEq(sellerBeforeBase - 1 ether, sellerAfterBase, "base sold for seller");

        assertEq(buyerBeforeQuote - 5e6, buyerAfterQuote, "quote gain for buyer");
        AuctionData memory data = auction.getAuctionData(aid);
        emit log_named_uint("lowestBase", data.lowestBase);
        emit log_named_uint("lowestQuote", data.lowestQuote);
    }

    function testAuctionRevealWrongKey() external {
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        bidder1.bidOnAuctionWithSalt(1 ether, 5e6, "hello");

        uint256[] memory bidIndices = new uint[](1);
        bidIndices[0] = 0;
        vm.warp(endTime + 1);

        vm.prank(address(seller));
        vm.expectRevert(ISizeSealed.InvalidPrivateKey.selector);
        auction.reveal(aid, 1, abi.encode(bidIndices, 1 ether, 5e6));
    }

    function testAuctionMultipleBidsFinalise() public {
        (uint256 sellerBeforeQuote, uint256 sellerBeforeBase) = seller.balances();
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        bidder2.setAuctionId(aid);
        (uint256 buyerBeforeQuote,) = bidder1.balances();
        (uint256 buyerBeforeQuote2,) = bidder2.balances();
        bidder1.bidOnAuctionWithSalt(1 ether, 5e6, "hello");
        bidder2.bidOnAuctionWithSalt(1 ether, 6e6, "hello2");
        uint256[] memory bidIndices = new uint[](2);
        bidIndices[0] = 1;
        bidIndices[1] = 0;
        vm.warp(endTime + 1);
        seller.finalize(bidIndices, 1 ether, 5e6);
        (uint256 sellerAfterQuote, uint256 sellerAfterBase) = seller.balances();
        (uint256 buyerAfterQuote,) = bidder1.balances();
        (uint256 buyerAfterQuote2,) = bidder2.balances();
        assertEq(sellerBeforeQuote, sellerAfterQuote - 5e6 - 5e6, "quote gain for seller");
        assertEq(sellerBeforeBase - 1 ether - 1 ether, sellerAfterBase, "base sold for seller");

        assertEq(buyerBeforeQuote - 5e6, buyerAfterQuote, "quote gain for buyer");
        assertEq(buyerBeforeQuote2 - 6e6, buyerAfterQuote2, "quote gain for buyer");
        AuctionData memory data = auction.getAuctionData(aid);
        emit log_named_uint("lowestBase", data.lowestBase);
        emit log_named_uint("lowestQuote", data.lowestQuote);
    }

    function testAuctionRefundLostBidder() public {
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        bidder1.setAuctionId(aid);
        bidder2.setAuctionId(aid);
        bidder1.bidOnAuctionWithSalt(5 ether, 2e6, "hello");
        bidder2.bidOnAuctionWithSalt(1 ether, 2e6, "hello");
        uint256[] memory bidIndices = new uint[](2);
        bidIndices[0] = 1;
        bidIndices[1] = 0;
        vm.warp(endTime + 1);
        (uint256 sellerBeforeQuote, uint256 sellerBeforeBase) = seller.balances();
        seller.finalize(bidIndices, 1 ether, 2e6);
        (uint256 sellerAfterQuote, uint256 sellerAfterBase) = seller.balances();
        assertEq(sellerBeforeQuote + 2e6, sellerAfterQuote, "quote gain for seller");
        assertEq(sellerBeforeBase + 9 ether, sellerAfterBase, "base refund for seller");

        // Winning bid can't refund
        vm.expectRevert(ISizeSealed.InvalidState.selector);
        bidder2.refund();
        (uint256 buyerBeforeQuote,) = bidder1.balances();
        bidder1.refund();
        (uint256 buyerAfterQuote,) = bidder1.balances();
        assertEq(buyerBeforeQuote + 2e6, buyerAfterQuote, "quote refund for buyer");
    }

    function testTokensAvailableForWithdrawal() public {
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        vm.warp(unlockTime - 1);
        assertEq(auction.tokensAvailableForWithdrawal(aid, 100e36), 0);
        vm.warp(unlockTime);
        assertEq(auction.tokensAvailableForWithdrawal(aid, 100e36), 0);

        vm.warp((unlockTime + unlockEnd) / 2);
        assertEq(auction.tokensAvailableForWithdrawal(aid, 100e36), 50e36);

        vm.warp(unlockEnd);
        assertEq(auction.tokensAvailableForWithdrawal(aid, 100e36), 100e36);
        vm.warp(unlockEnd + 1);
        assertEq(auction.tokensAvailableForWithdrawal(aid, 100e36), 100e36);
    }

    function test50CliffAndLinearWithdrawal() public {
        cliffPercent = 0.5e18;
        uint256 aid = seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, cliffPercent
        );
        vm.warp(unlockTime - 1);
        assertEq(auction.tokensAvailableForWithdrawal(aid, 1e36), 0);
        vm.warp(unlockTime);
        assertEq(auction.tokensAvailableForWithdrawal(aid, 100e36), 0);

        vm.warp(unlockTime + 1);
        uint256 singleSecondVesting = 50e36 / (unlockEnd - unlockTime);
        assertEq(auction.tokensAvailableForWithdrawal(aid, 100e36), 50e36 + singleSecondVesting);

        vm.warp((unlockTime + unlockEnd) / 2);
        assertEq(auction.tokensAvailableForWithdrawal(aid, 100e36), 75e36);

        vm.warp(unlockEnd);
        assertEq(auction.tokensAvailableForWithdrawal(aid, 100e36), 100e36);
        vm.warp(unlockEnd + 1);
        assertEq(auction.tokensAvailableForWithdrawal(aid, 100e36), 100e36);
    }

    function test100CliffWithdrawal() public {
        uint32 unlockCliffStart = uint32(block.timestamp + 100);
        uint32 unlockCliffEnd = unlockCliffStart;
        uint256 aid = seller.createAuction(
            baseToSell,
            reserveQuotePerBase,
            minimumBidQuote,
            startTime,
            endTime,
            unlockCliffStart,
            unlockCliffEnd,
            0.98e18
        );
        vm.warp(unlockCliffStart);
        assertEq(auction.tokensAvailableForWithdrawal(aid, 100), 0);
        vm.warp(unlockCliffStart + 1);
        assertEq(auction.tokensAvailableForWithdrawal(aid, 100), 100);
    }

    function testSingleWhitelistBid() public {
        Merkle m = new Merkle();
        bytes32[] memory data = new bytes32[](2);
        data[0] = keccak256(abi.encodePacked(address(bidder1)));
        data[1] = keccak256(abi.encodePacked(address(bidder2)));

        // Use murky library to generate merkleRoot & proof for bidder1
        bytes32 root = m.getRoot(data);
        bytes32[] memory proof1 = m.getProof(data, 0);
        bytes32[] memory proof2 = m.getProof(data, 1);

        uint256 aid = seller.createAuctionWhitelist(
            baseToSell,
            reserveQuotePerBase,
            minimumBidQuote,
            startTime,
            endTime,
            unlockTime,
            unlockEnd,
            cliffPercent,
            root
        );
        bidder1.setAuctionId(aid);
        bidder1.bidOnWhitelistAuctionWithSalt(1 ether, 2e6, "hello", proof1);
        bidder2.setAuctionId(aid);
        bidder2.bidOnWhitelistAuctionWithSalt(1 ether, 3e6, "hello2", proof2);
        bidder3.setAuctionId(aid);
        vm.expectRevert(ISizeSealed.InvalidProof.selector);
        bidder3.bidOnWhitelistAuctionWithSalt(1 ether, 3e6, "hello3", proof2);
    }

    function testInvalidTimestamps() public {
        // Test 101% cliff
        vm.expectRevert(ISizeSealed.InvalidCliffPercent.selector);
        seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockTime, unlockEnd, 1.01e18
        );

        // Test vestingTimings swapped with auctionTimings
        vm.expectRevert(ISizeSealed.InvalidTimestamp.selector);
        seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, unlockTime, unlockEnd, startTime, endTime, 0.5e18
        );

        // Test unlock period larger than auction period
        vm.expectRevert(ISizeSealed.InvalidTimestamp.selector);
        uint32 future = uint32(block.timestamp + 1000000);
        seller.createAuction(baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, 0, future, 0.5e18);

        // Test startAuction and endAuction being swapped
        vm.expectRevert(ISizeSealed.InvalidTimestamp.selector);
        seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, endTime, startTime, unlockTime, unlockEnd, cliffPercent
        );

        // Test startVest swapped with vestingEnd
        vm.expectRevert(ISizeSealed.InvalidTimestamp.selector);
        seller.createAuction(
            baseToSell, reserveQuotePerBase, minimumBidQuote, startTime, endTime, unlockEnd, unlockTime, cliffPercent
        );
    }

    function toUint256(bytes memory _bytes) internal pure returns (uint256) {
        uint256 tempUint;
        assembly {
            tempUint := mload(add(add(_bytes, 0x20), 0))
        }
        return tempUint;
    }
}
