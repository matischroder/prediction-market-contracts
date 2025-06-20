import { ethers } from "hardhat";

async function main() {
  // Replace with your deployed contract addresses
  const MARKET_FACTORY_ADDRESS = "0x..."; // Replace with deployed address
  const USDC_ADDRESS = "0x..."; // Replace with deployed address

  const [user] = await ethers.getSigners();
  console.log("Interacting with contracts as:", user.address);

  // Get contract instances
  const MarketFactory = await ethers.getContractFactory("MarketFactory");
  const marketFactory = MarketFactory.attach(MARKET_FACTORY_ADDRESS);

  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const usdc = MockERC20.attach(USDC_ADDRESS);

  // Get all markets
  const markets = await marketFactory.getAllMarkets();
  console.log("Available markets:", markets.length);

  if (markets.length > 0) {
    const marketAddress = markets[0];
    console.log("Interacting with market:", marketAddress);

    // Get market contract
    const PredictionMarket = await ethers.getContractFactory(
      "PredictionMarket"
    );
    const market = PredictionMarket.attach(marketAddress);

    // Get market info
    const marketInfo = await market.getMarketInfo();
    console.log("Market question:", marketInfo._question);
    console.log(
      "Resolution time:",
      new Date(marketInfo._resolutionTime.toNumber() * 1000)
    );
    console.log(
      "Total YES bets:",
      ethers.utils.formatUnits(marketInfo._totalYesBets, 6)
    );
    console.log(
      "Total NO bets:",
      ethers.utils.formatUnits(marketInfo._totalNoBets, 6)
    );
    console.log("Is resolved:", marketInfo._isResolved);

    // Get current odds
    const odds = await market.getCurrentOdds();
    console.log("YES odds:", odds.yesOdds.toString() / 100, "%");
    console.log("NO odds:", odds.noOdds.toString() / 100, "%");

    // Check USDC balance
    const balance = await usdc.balanceOf(user.address);
    console.log("USDC balance:", ethers.utils.formatUnits(balance, 6));

    // Place a bet (uncomment to execute)
    /*
    const betAmount = ethers.utils.parseUnits("100", 6); // 100 USDC
    
    // Approve USDC spending
    await usdc.approve(marketAddress, betAmount);
    console.log("Approved USDC spending");
    
    // Place YES bet
    await market.placeBet(true, betAmount);
    console.log("Placed 100 USDC YES bet");
    
    // Check updated market info
    const updatedInfo = await market.getMarketInfo();
    console.log("Updated YES bets:", ethers.utils.formatUnits(updatedInfo._totalYesBets, 6));
    */
  }

  // Create a new market (uncomment to execute)
  /*
  const futureTime = Math.floor(Date.now() / 1000) + 86400 * 7; // 7 days from now
  await marketFactory.createMarket(
    "Will Bitcoin reach $100k by next week?",
    futureTime
  );
  console.log("Created new market");
  */
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
