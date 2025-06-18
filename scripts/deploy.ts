import { ethers } from "hardhat";

async function main() {
  console.log("Deploying Prediction Market contracts...");

  // Get deployer
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // Deploy MockERC20 for testing (USDC)
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const usdc = await MockERC20.deploy("USD Coin", "USDC", 6);
  await usdc.deployed();
  console.log("MockUSDC deployed to:", usdc.address);

  // Chainlink configuration (Mumbai testnet addresses)
  const VRF_COORDINATOR = "0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed"; // Mumbai
  const LINK_TOKEN = "0x326C977E6efc84E512bB9C30f76E30c160eD06FB"; // Mumbai
  const KEY_HASH = "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f"; // Mumbai
  const SUBSCRIPTION_ID = 1; // Replace with your subscription ID
  const PRICE_FEED = "0x0715A7794a1dc8e42615F059dD6e406A6594651A"; // ETH/USD Mumbai

  // Deploy ProofOfReservesGuard
  const ProofOfReservesGuard = await ethers.getContractFactory("ProofOfReservesGuard");
  const porGuard = await ProofOfReservesGuard.deploy();
  await porGuard.deployed();
  console.log("ProofOfReservesGuard deployed to:", porGuard.address);

  // Deploy CCIPBridge
  const CCIP_ROUTER = "0x70499c328e1E2a3c41108bd3730F6670a44595D1"; // Mumbai
  const CCIPBridge = await ethers.getContractFactory("CCIPBridge");
  const ccipBridge = await CCIPBridge.deploy(CCIP_ROUTER, LINK_TOKEN);
  await ccipBridge.deployed();
  console.log("CCIPBridge deployed to:", ccipBridge.address);

  // Deploy ChainlinkFunctions
  const FUNCTIONS_ROUTER = "0x6E2dc0F9DB014aE19888F539E59285D2Ea04244C"; // Mumbai
  const ChainlinkFunctions = await ethers.getContractFactory("ChainlinkFunctions");
  const chainlinkFunctions = await ChainlinkFunctions.deploy(FUNCTIONS_ROUTER);
  await chainlinkFunctions.deployed();
  console.log("ChainlinkFunctions deployed to:", chainlinkFunctions.address);

  // Deploy MarketFactory
  const MarketFactory = await ethers.getContractFactory("MarketFactory");
  const marketFactory = await MarketFactory.deploy(
    usdc.address,
    PRICE_FEED,
    VRF_COORDINATOR,
    KEY_HASH,
    SUBSCRIPTION_ID
  );
  await marketFactory.deployed();
  console.log("MarketFactory deployed to:", marketFactory.address);

  // Create a sample market
  const resolutionTime = Math.floor(Date.now() / 1000) + 86400; // 24 hours from now
  const tx = await marketFactory.createMarket(
    "Will ETH price be above $3000 by tomorrow?",
    resolutionTime
  );
  await tx.wait();

  const marketCount = await marketFactory.getMarketsCount();
  const markets = await marketFactory.getAllMarkets();
  console.log("Sample market created at:", markets[marketCount.toNumber() - 1]);

  // Mint some USDC to deployer for testing
  await usdc.mint(deployer.address, ethers.utils.parseUnits("10000", 6));
  console.log("Minted 10,000 USDC to deployer");

  console.log("\n=== Deployment Summary ===");
  console.log("MockUSDC:", usdc.address);
  console.log("ProofOfReservesGuard:", porGuard.address);
  console.log("CCIPBridge:", ccipBridge.address);
  console.log("ChainlinkFunctions:", chainlinkFunctions.address);
  console.log("MarketFactory:", marketFactory.address);
  console.log("Sample Market:", markets[marketCount.toNumber() - 1]);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
