import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { MarketFactory, PredictionMarket, MockERC20 } from "../typechain-types";

describe("PredictionMarket", function () {
  let marketFactory: MarketFactory;
  let usdc: MockERC20;
  let market: PredictionMarket;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;

  const INITIAL_USDC_AMOUNT = ethers.utils.parseUnits("10000", 6);
  const BET_AMOUNT = ethers.utils.parseUnits("100", 6);

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy MockUSDC
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    usdc = await MockERC20.deploy("USD Coin", "USDC", 6);

    // Mock addresses for testing
    const mockPriceFeed = "0x0000000000000000000000000000000000000001";
    const mockVRFCoordinator = "0x0000000000000000000000000000000000000002";
    const mockKeyHash =
      "0x0000000000000000000000000000000000000000000000000000000000000001";
    const mockSubscriptionId = 1;

    // Deploy MarketFactory
    const MarketFactory = await ethers.getContractFactory("MarketFactory");
    marketFactory = await MarketFactory.deploy(
      usdc.address,
      mockPriceFeed,
      mockVRFCoordinator,
      mockKeyHash,
      mockSubscriptionId
    );

    // Create a market
    const resolutionTime = Math.floor(Date.now() / 1000) + 86400; // 24 hours from now
    await marketFactory.createMarket(
      "Will ETH price be above $3000?",
      resolutionTime
    );

    const markets = await marketFactory.getAllMarkets();
    const PredictionMarket = await ethers.getContractFactory(
      "PredictionMarket"
    );
    market = PredictionMarket.attach(markets[0]);

    // Mint USDC to users
    await usdc.mint(user1.address, INITIAL_USDC_AMOUNT);
    await usdc.mint(user2.address, INITIAL_USDC_AMOUNT);
  });

  describe("Market Creation", function () {
    it("Should create a market with correct parameters", async function () {
      const marketInfo = await market.getMarketInfo();
      expect(marketInfo._question).to.equal("Will ETH price be above $3000?");
      expect(marketInfo._isResolved).to.be.false;
    });

    it("Should track market count correctly", async function () {
      const initialCount = await marketFactory.getMarketsCount();

      const resolutionTime = Math.floor(Date.now() / 1000) + 86400;
      await marketFactory.createMarket("Test market 2", resolutionTime);

      const newCount = await marketFactory.getMarketsCount();
      expect(newCount).to.equal(initialCount.add(1));
    });
  });

  describe("Betting", function () {
    beforeEach(async function () {
      // Approve USDC spending for users
      await usdc.connect(user1).approve(market.address, INITIAL_USDC_AMOUNT);
      await usdc.connect(user2).approve(market.address, INITIAL_USDC_AMOUNT);
    });

    it("Should allow users to place YES bets", async function () {
      await market.connect(user1).placeBet(true, BET_AMOUNT);

      const marketInfo = await market.getMarketInfo();
      expect(marketInfo._totalYesBets).to.equal(BET_AMOUNT);
      expect(marketInfo._totalNoBets).to.equal(0);
    });

    it("Should allow users to place NO bets", async function () {
      await market.connect(user1).placeBet(false, BET_AMOUNT);

      const marketInfo = await market.getMarketInfo();
      expect(marketInfo._totalYesBets).to.equal(0);
      expect(marketInfo._totalNoBets).to.equal(BET_AMOUNT);
    });

    it("Should calculate odds correctly", async function () {
      await market.connect(user1).placeBet(true, BET_AMOUNT);
      await market.connect(user2).placeBet(false, BET_AMOUNT.mul(2));

      const odds = await market.getCurrentOdds();
      // With 100 YES and 200 NO, YES should get 66.67% and NO 33.33%
      expect(odds.yesOdds).to.be.closeTo(6667, 10); // Allow small rounding error
      expect(odds.noOdds).to.be.closeTo(3333, 10);
    });

    it("Should emit BetPlaced event", async function () {
      await expect(market.connect(user1).placeBet(true, BET_AMOUNT))
        .to.emit(market, "BetPlaced")
        .withArgs(user1.address, true, BET_AMOUNT);
    });

    it("Should reject bets with zero amount", async function () {
      await expect(market.connect(user1).placeBet(true, 0)).to.be.revertedWith(
        "Amount must be greater than 0"
      );
    });
  });

  describe("Multiple Markets", function () {
    it("Should return correct market range", async function () {
      // Create additional markets
      const resolutionTime = Math.floor(Date.now() / 1000) + 86400;
      await marketFactory.createMarket("Market 2", resolutionTime);
      await marketFactory.createMarket("Market 3", resolutionTime);

      const markets = await marketFactory.getMarketsByRange(0, 2);
      expect(markets.length).to.equal(3);
    });

    it("Should reject invalid range", async function () {
      await expect(marketFactory.getMarketsByRange(5, 10)).to.be.revertedWith(
        "Invalid range"
      );
    });
  });

  describe("Market Info", function () {
    it("Should return default odds for empty market", async function () {
      const odds = await market.getCurrentOdds();
      expect(odds.yesOdds).to.equal(5000); // 50%
      expect(odds.noOdds).to.equal(5000); // 50%
    });
  });
});
