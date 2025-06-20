import { ethers } from "hardhat";

async function main() {
  console.log("Deploying Prediction Market contracts...");

  // Get deployer
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // Deploy MockERC20 for testing (USDC)
  const MockERC20 = await ethers.getContractFactory("MockERC20");
  const usdc = await MockERC20.deploy("USD Coin", "USDC", 6);
  await usdc.waitForDeployment();
  const usdcAddress = await usdc.getAddress();
  console.log("MockUSDC deployed to:", usdcAddress);

  // Chainlink configuration (Sepolia testnet addresses)
  const VRF_COORDINATOR = "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625"; // Sepolia
  const LINK_TOKEN = "0x779877A7B0D9E8603169DdbD7836e478b4624789"; // Sepolia
  const KEY_HASH =
    "0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4"; // Sepolia
  const SUBSCRIPTION_ID = 1; // Tu subId de VRF en Sepolia
  const PRICE_FEED = "0x694AA1769357215DE4FAC081bf1f309aDC325306"; // ETH/USD Sepolia

  // Deploy ProofOfReservesGuard
  const ProofOfReservesGuard = await ethers.getContractFactory(
    "ProofOfReservesGuard"
  );
  const porGuard = await ProofOfReservesGuard.deploy();
  await porGuard.waitForDeployment();
  const porGuardAddress = await porGuard.getAddress();
  console.log("ProofOfReservesGuard deployed to:", porGuardAddress);

  // Deploy CCIPBridge
  const CCIPBridge = await ethers.getContractFactory("CCIPBridge");
  const CCIP_ROUTER = "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59"; // Sepolia CCIP Router
  const ccipBridge = await CCIPBridge.deploy(CCIP_ROUTER, LINK_TOKEN);
  await ccipBridge.waitForDeployment();
  console.log("CCIPBridge deployed to:", await ccipBridge.getAddress());

  // Deploy ChainlinkFunctions
  const ChainlinkFunctions = await ethers.getContractFactory(
    "ChainlinkFunctions"
  );
  const FUNCTIONS_ROUTER = "0x6E2dc0F9DB014aE19888F539E59285D2Ea04244C"; // Sepolia Functions Router
  const chainlinkFunctions = await ChainlinkFunctions.deploy(FUNCTIONS_ROUTER);
  await chainlinkFunctions.waitForDeployment();
  console.log(
    "ChainlinkFunctions deployed to:",
    await chainlinkFunctions.getAddress()
  );

  // Deploy MarketFactory
  const MarketFactory = await ethers.getContractFactory("MarketFactory");
  const marketFactory = await MarketFactory.deploy(
    usdcAddress,
    PRICE_FEED,
    VRF_COORDINATOR,
    KEY_HASH,
    SUBSCRIPTION_ID
  );
  await marketFactory.waitForDeployment();
  const marketFactoryAddress = await marketFactory.getAddress();
  console.log("MarketFactory deployed to:", marketFactoryAddress);

  // Create a sample market
  const resolutionTime = Math.floor(Date.now() / 1000) + 86400; // 24 hours from now
  const tx = await marketFactory.createMarket(
    "Will ETH price be above $3000 by tomorrow?",
    resolutionTime
  );
  await tx.wait();

  const marketCount = await marketFactory.getMarketsCount();
  const markets = await marketFactory.getAllMarkets();
  console.log("Sample market created at:", markets[Number(marketCount) - 1]);

  // Mint some USDC to deployer for testing
  await usdc.mint(deployer.address, ethers.parseUnits("10000", 6));
  console.log("Minted 10,000 USDC to deployer");

  console.log("\n=== Deployment Summary ===");
  console.log("MockUSDC:", usdcAddress);
  console.log("ProofOfReservesGuard:", porGuardAddress);
  console.log("MarketFactory:", marketFactoryAddress);
  console.log("Sample Market:", markets[Number(marketCount) - 1]);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
