import { ethers, network } from "hardhat";

async function main() {
  console.log("🚀 Deploying Prediction Market contracts...");
  console.log("📡 Network:", network.name);

  // Get deployer
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  const balance = await deployer.provider.getBalance(deployer.address);
  console.log("Account balance:", ethers.formatEther(balance), "ETH");

  // Detectar el tipo de red
  const isLocalNetwork =
    network.name === "hardhat" || network.name === "localhost";
  // Cast para acceder a forking config
  const networkConfig = network.config as any;
  const isSepoliaFork =
    network.name === "hardhat" &&
    networkConfig.forking?.url?.includes("sepolia");
  const isRealSepolia = network.name === "sepolia";

  console.log("📍 Network Detection:");
  console.log(`   Network name: ${network.name}`);
  console.log(`   Chain ID: ${network.config.chainId}`);
  console.log(`   Is local: ${isLocalNetwork}`);
  console.log(`   Is Sepolia fork: ${isSepoliaFork}`);
  console.log(`   Is real Sepolia: ${isRealSepolia}`);

  // Configuración de Chainlink según la red
  let CHAINLINK_CONFIG;
  let PRICE_FEEDS;
  let shouldDeployMockUSDC = true;

  if (isSepoliaFork || isRealSepolia) {
    // Configuración real de Sepolia
    console.log("🔗 Using Sepolia Chainlink configuration");
    CHAINLINK_CONFIG = {
      VRF_COORDINATOR: "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625", // Sepolia VRF Coordinator
      LINK_TOKEN: "0x779877A7B0D9E8603169DdbD7836e478b4624789", // Sepolia LINK token
      KEY_HASH:
        "0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c", // Sepolia 30 gwei key hash
      SUBSCRIPTION_ID: ethers.toBigInt(1), // You'll need to create this
      AUTOMATION_REGISTRAR: "0xb0E49c5D0d05cbc241d68c05BC5BA1d1B7B72976", // Sepolia Automation Registrar
    };

    PRICE_FEEDS = {
      "BTC/USD": "0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43", // Sepolia BTC/USD
      "ETH/USD": "0x694AA1769357215DE4FAC081bf1f309aDC325306", // Sepolia ETH/USD
      "LINK/USD": "0xc59E3633BAAC79493d908e63626716e204A45EdF", // Sepolia LINK/USD
    };
  } else {
    // Configuración mock para localhost puro
    console.log("🏠 Using localhost mock configuration");
    CHAINLINK_CONFIG = {
      VRF_COORDINATOR: "0x5FbDB2315678afecb367f032d93F642f64180aa3", // Mock address
      LINK_TOKEN: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512", // Mock address
      KEY_HASH:
        "0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4", // Any valid hash
      SUBSCRIPTION_ID: ethers.toBigInt(1), // Mock subscription
      AUTOMATION_REGISTRAR: "0x0000000000000000000000000000000000000000", // No automation in localhost
    };

    PRICE_FEEDS = {
      "BTC/USD": deployer.address, // Mock - usar deployer como mock
      "ETH/USD": deployer.address, // Mock - usar deployer como mock
      "LINK/USD": deployer.address, // Mock - usar deployer como mock
    };
  }

  // Deploy MockERC20 for testing (USDC) - solo si no estamos en red real
  let usdcAddress;
  let usdc; // Declarar la variable usdc aquí
  if (shouldDeployMockUSDC) {
    console.log("\n📄 Deploying MockUSDC...");
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    usdc = await MockERC20.deploy("USD Coin", "USDC", 6);
    await usdc.waitForDeployment();
    usdcAddress = await usdc.getAddress();
    console.log("✅ MockUSDC deployed to:", usdcAddress);
  } else {
    // En red real, usar USDC real de Sepolia si existe o deploy mock
    console.log("\n📄 Using MockUSDC for Sepolia testing...");
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    usdc = await MockERC20.deploy("USD Coin", "USDC", 6);
    await usdc.waitForDeployment();
    usdcAddress = await usdc.getAddress();
    console.log("✅ MockUSDC deployed to:", usdcAddress);
  }

  // Deploy MarketFactory
  console.log("\n🏭 Deploying MarketFactory...");
  const MarketFactory = await ethers.getContractFactory("MarketFactory");
  const marketFactory = await MarketFactory.deploy(
    usdcAddress, // _bettingToken (USDC)
    CHAINLINK_CONFIG.LINK_TOKEN, // _linkToken
    CHAINLINK_CONFIG.VRF_COORDINATOR, // _vrfCoordinator
    CHAINLINK_CONFIG.KEY_HASH, // _keyHash
    CHAINLINK_CONFIG.SUBSCRIPTION_ID, // _subscriptionId
    CHAINLINK_CONFIG.AUTOMATION_REGISTRAR // _automationRegistrar
  );
  await marketFactory.waitForDeployment();
  const marketFactoryAddress = await marketFactory.getAddress();
  console.log("✅ MarketFactory deployed to:", marketFactoryAddress);

  // Fund the factory with some ETH for Automation
  console.log("\n💰 Funding MarketFactory with ETH for Automation...");
  const ethAmount = isRealSepolia ? "0.001" : "0.1"; // Solo 0.001 ETH para Sepolia real
  const depositETHTx = await marketFactory.depositETH({
    value: ethers.parseEther(ethAmount),
  });
  await depositETHTx.wait();
  console.log(`✅ MarketFactory funded with ${ethAmount} ETH`);

  // Fund factory with LINK for VRF
  console.log("\n🔗 LINK funding...");
  if (isSepoliaFork) {
    console.log("🚧 Sepolia Fork Mode - LINK funding simulation");
    console.log(
      "   This is a fork of Sepolia, so real LINK contracts exist but we may not have LINK tokens"
    );
    console.log("   For full testing, you would need to:");
    console.log("   1. Create VRF subscription at https://vrf.chain.link/");
    console.log("   2. Fund subscription with LINK");
    console.log("   3. Add MarketFactory as consumer");
    console.log("   ⚠️  Skipping actual LINK deposit for now");
  } else if (isRealSepolia) {
    console.log("🌐 Real Sepolia Network - LINK funding required");
    console.log("   You MUST complete these steps for VRF to work:");
    console.log(
      "   1. Get Sepolia LINK tokens from faucet: https://faucets.chain.link/"
    );
    console.log("   2. Create VRF subscription: https://vrf.chain.link/");
    console.log("   3. Fund your subscription with LINK");
    console.log("   4. Add MarketFactory as consumer");
    console.log("   5. Update SUBSCRIPTION_ID in this script");
    console.log("   ⚠️  Skipping LINK deposit - do this manually");
  } else {
    console.log("🏠 Local Network - Skipping LINK funding");
    console.log(
      "   In localhost mode, VRF calls will fail but deploy succeeds"
    );
    console.log("   This is for contract deployment testing only");
  }

  // Mint some USDC to deployer for testing
  console.log("\n🪙 Minting test USDC...");
  const mintAmount = ethers.parseUnits("10000", 6); // 10,000 USDC
  await usdc.mint(deployer.address, mintAmount);
  console.log("✅ Minted 10,000 USDC to deployer"); // Create a test market (commented out until LINK funding is resolved)
  console.log("\n🎯 Test market creation...");
  console.log("⚠️  Skipping market creation - requires LINK funding first");
  console.log("   To create a market after funding LINK:");
  console.log(`   await marketFactory.createMarket(`);
  console.log(`     "${PRICE_FEEDS["BTC/USD"]}", // priceFeed`);
  console.log(`     "BTC", // assetName`);
  console.log(`     "USD", // baseAsset`);
  console.log(`     ethers.parseUnits("100000", 8), // targetPrice`);
  console.log(`     ${Math.floor(Date.now() / 1000) + 3600} // resolutionTime`);
  console.log(`   );`);

  let testMarketAddress = "Not created - needs LINK funding";

  // Deploy summary
  console.log("\n" + "=".repeat(50));
  console.log("🎉 DEPLOYMENT COMPLETE!");
  console.log("=".repeat(50));
  console.log("📋 Contract Addresses:");
  console.log("   MockUSDC:", usdcAddress);
  console.log("   MarketFactory:", marketFactoryAddress);
  console.log("   Test Market:", testMarketAddress);
  console.log("\n📊 Price Feeds Available:");
  Object.entries(PRICE_FEEDS).forEach(([pair, address]) => {
    console.log(`   ${pair}: ${address}`);
  });
  console.log("\n🔧 Next Steps:");
  if (isSepoliaFork) {
    console.log("📋 Sepolia Fork Mode:");
    console.log("1. Update frontend .env with these addresses");
    console.log("2. Get USDC: await usdc.mint(yourAddress, amount)");
    console.log("3. Test with real Chainlink price feeds (but mock VRF)");
    console.log("4. For full VRF testing, switch to real Sepolia");
  } else if (isRealSepolia) {
    console.log("🌐 Real Sepolia Mode:");
    console.log(
      "1. Complete VRF subscription setup (see LINK funding section above)"
    );
    console.log("2. Update frontend .env with these addresses");
    console.log("3. Get Sepolia ETH from faucet for transactions");
    console.log("4. Test full functionality with real Chainlink services");
  } else {
    console.log("🏠 Local Mode:");
    console.log("1. Update frontend .env with these addresses");
    console.log("2. Get USDC: await usdc.mint(yourAddress, amount)");
    console.log(
      "3. Test basic functionality (price feeds and VRF will be mocked)"
    );
    console.log(
      "4. Run 'npx hardhat run scripts/deploy.ts --network sepolia' for real testing"
    );
  }

  console.log("\n📝 Available Commands:");
  console.log(
    "   Sepolia fork (recommended): npx hardhat run scripts/deploy.ts --network hardhat"
  );
  console.log(
    "   Pure localhost: Use hardhat.config.local.ts + npx hardhat run scripts/deploy.ts --network hardhat"
  );
  console.log(
    "   Real Sepolia: npx hardhat run scripts/deploy.ts --network sepolia"
  );
  console.log("\n📖 See DEPLOYMENT.md for complete guide and use cases");

  // Save addresses to JSON file
  const networkType = isSepoliaFork
    ? "sepolia-fork"
    : isRealSepolia
    ? "sepolia"
    : "localhost";
  const addresses = {
    network: networkType,
    chainId: network.config.chainId,
    deployedAt: new Date().toISOString(),
    contracts: {
      mockUSDC: usdcAddress,
      marketFactory: marketFactoryAddress,
      testMarket: testMarketAddress,
    },
    priceFeeds: PRICE_FEEDS,
    chainlink: {
      VRF_COORDINATOR: CHAINLINK_CONFIG.VRF_COORDINATOR,
      LINK_TOKEN: CHAINLINK_CONFIG.LINK_TOKEN,
      KEY_HASH: CHAINLINK_CONFIG.KEY_HASH,
      SUBSCRIPTION_ID: Number(CHAINLINK_CONFIG.SUBSCRIPTION_ID), // Convert BigInt to number
      AUTOMATION_REGISTRAR: CHAINLINK_CONFIG.AUTOMATION_REGISTRAR,
    },
    isProduction: isRealSepolia,
    isFork: isSepoliaFork,
    isLocal: !isSepoliaFork && !isRealSepolia,
  };

  const fs = require("fs");
  fs.writeFileSync(
    "deployed-addresses.json",
    JSON.stringify(addresses, null, 2)
  );
  console.log("💾 Addresses saved to deployed-addresses.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
