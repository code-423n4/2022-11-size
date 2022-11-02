// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {DSTest} from "ds-test/test.sol";

import {MockERC20} from "./MockERC20.sol";
import {ECCMath} from "../../util/ECCMath.sol";
import {SizeSealed} from "../../SizeSealed.sol";
import {ISizeSealed} from "../../interfaces/ISizeSealed.sol";

contract MockBuyer is ISizeSealed, DSTest {

    SizeSealed auctionContract;

    uint256 auctionId;
    uint256 lastBidIndex;
    uint128 baseAmount;
    bytes16 salt;

    ECCMath.Point publicKey;

    MockERC20 quoteToken;
    MockERC20 baseToken;

    uint256 constant SELLER_PRIVATE_KEY = uint256(keccak256("Size Seller"));
    uint256 constant BUYER_PRIVATE_KEY = uint256(keccak256("Size Buyer"));

    constructor(address _auction_contract, MockERC20 _quoteToken, MockERC20 _baseToken) {
        auctionContract = SizeSealed(_auction_contract);

        quoteToken = _quoteToken;
        baseToken = _baseToken;
        publicKey = ECCMath.publicKey(BUYER_PRIVATE_KEY);
        salt = bytes16(keccak256(abi.encode("randomsalt")));
        // Mint quote tokens (USDC to ourselves)
        mintQuote(100 ether);
    }

    function setAuctionId(uint256 _aid) external {
        auctionId = _aid;
    }

    function bidOnAuction(uint128 _baseAmount, uint128 quoteAmount) public returns (uint256) {
        require(quoteToken.balanceOf(address(this)) >= quoteAmount);
        baseAmount = _baseAmount;
        bytes32 message = auctionContract.computeMessage(baseAmount, salt);
        (, bytes32 encryptedMessage) =
            ECCMath.encryptMessage(ECCMath.publicKey(SELLER_PRIVATE_KEY), BUYER_PRIVATE_KEY, message);

        lastBidIndex = auctionContract.bid(
            auctionId,
            quoteAmount,
            auctionContract.computeCommitment(message),
            publicKey,
            encryptedMessage,
            "",
            new bytes32[](0)
        );
        return lastBidIndex;
    }

    function bidOnWhitelistAuctionWithSalt(
        uint128 _baseAmount,
        uint128 quoteAmount,
        bytes16 _salt,
        bytes32[] calldata proof
    ) public returns (uint256) {
        baseAmount = _baseAmount;
        salt = _salt;
        bytes32 message = auctionContract.computeMessage(baseAmount, _salt);
        (, bytes32 encryptedMessage) =
            ECCMath.encryptMessage(ECCMath.publicKey(SELLER_PRIVATE_KEY), BUYER_PRIVATE_KEY, message);

        lastBidIndex = auctionContract.bid(
            auctionId, quoteAmount, auctionContract.computeCommitment(message), publicKey, encryptedMessage, "", proof
        );
        return lastBidIndex;
    }

    function bidOnAuctionWithSalt(uint128 _baseAmount, uint128 quoteAmount, bytes16 _salt) public returns (uint256) {
        require(quoteToken.balanceOf(address(this)) >= quoteAmount);
        baseAmount = _baseAmount;
        salt = _salt;
        bytes32 message = auctionContract.computeMessage(baseAmount, _salt);
        (, bytes32 encryptedMessage) =
            ECCMath.encryptMessage(ECCMath.publicKey(SELLER_PRIVATE_KEY), BUYER_PRIVATE_KEY, message);

        lastBidIndex = auctionContract.bid(
            auctionId,
            quoteAmount,
            auctionContract.computeCommitment(message),
            publicKey,
            encryptedMessage,
            "",
            new bytes32[](0)
        );
        return lastBidIndex;
    }

    function balances() public view returns (uint256, uint256) {
        return (quoteToken.balanceOf(address(this)), baseToken.balanceOf(address(this)));
    }

    // withdraw the last bid we just made
    function withdraw() public {
        SizeSealed(auctionContract).withdraw(auctionId, lastBidIndex);
    }

    function refund() public {
        SizeSealed(auctionContract).refund(auctionId, lastBidIndex);
    }

    function cancel() public {
        SizeSealed(auctionContract).cancelBid(auctionId, lastBidIndex);
    }

    function mintQuote(uint256 amount) public {
        quoteToken.mint(address(this), amount);
        quoteToken.approve(address(auctionContract), type(uint256).max);
    }
}
