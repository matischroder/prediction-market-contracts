import { run } from "hardhat";

async function main() {
  // Direcciones de los contratos desplegados en Sepolia
  const MARKET_FACTORY = "0x60368c98050e27F7A604d0eB27D7f88dCd864721";
  const MOCK_USDC = "0x9056C81f6AE73a45138348F4b4655BA7840a487D";

  // Chainlink Sepolia addresses
  const LINK_TOKEN = "0x779877A7B0D9E8603169DdbD7836e478b4624789";
  const VRF_COORDINATOR = "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625";
  const KEY_HASH =
    "0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c";
  const SUBSCRIPTION_ID = 1;

  console.log("🔍 Starting contract verification...");

  try {
    // Verificar MarketFactory
    console.log("📋 Verifying MarketFactory...");
    await run("verify:verify", {
      address: MARKET_FACTORY,
      constructorArguments: [
        MOCK_USDC,
        LINK_TOKEN,
        VRF_COORDINATOR,
        KEY_HASH,
        SUBSCRIPTION_ID,
      ],
      contract: "contracts/MarketFactory.sol:MarketFactory", // Especificar contrato exacto
    });
    console.log("✅ MarketFactory verified!");

    // Verificar MockUSDC
    console.log("💰 Verifying MockUSDC...");
    await run("verify:verify", {
      address: MOCK_USDC,
      constructorArguments: [],
      contract: "contracts/mocks/MockERC20.sol:MockERC20", // Especificar contrato exacto
    });
    console.log("✅ MockUSDC verified!");

  } catch (error: any) {
    if (error.message.includes("Already Verified")) {
      console.log("✅ Contract already verified!");
    } else {
      console.error("❌ Verification failed:", error.message);
      console.log("\n🔧 Try manual verification:");
      console.log("1. Go to: https://sepolia.etherscan.io/address/0x60368c98050e27F7A604d0eB27D7f88dCd864721#code");
      console.log("2. Click 'Contract' → 'Verify and Publish'");
      console.log("3. Use these settings:");
      console.log("   - Compiler: v0.8.19");
      console.log("   - Optimization: Yes, 200 runs");
      console.log("   - Via IR: Yes");
      console.log("4. Use flattened source from: npx hardhat flatten contracts/MarketFactory.sol");
      console.log("5. Constructor args: 0000000000000000000000009056c81f6ae73a45138348f4b4655ba7840a487d000000000000000000000000779877a7b0d9e8603169ddbd7836e478b4624789000000000000000000000000008103b0a8a00be2ddc778e6e7eaa21791cd364625474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c0000000000000000000000000000000000000000000000000000000000000001");
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
