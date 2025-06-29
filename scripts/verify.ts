import { run } from "hardhat";
import * as fs from "fs";
import * as path from "path";

// Leer direcciones desde deployed-addresses.json
function loadDeployedAddresses() {
    const addressesPath = path.join(__dirname, "../deployed-addresses.json");

    if (!fs.existsSync(addressesPath)) {
        throw new Error("❌ deployed-addresses.json not found. Please deploy contracts first.");
    }

    const addresses = JSON.parse(fs.readFileSync(addressesPath, "utf8"));
    return addresses;
}

async function main() {
    console.log("📖 Loading deployed contract addresses...");
    const deployedAddresses = loadDeployedAddresses();

    // Extraer direcciones de los contratos
    const MARKET_FACTORY = deployedAddresses.contracts.marketFactory;
    const NOSTRONET = deployedAddresses.contracts.nostronet;

    // Chainlink addresses desde deployed-addresses.json
    const LINK_TOKEN = deployedAddresses.chainlink.LINK_TOKEN;
    const VRF_COORDINATOR = deployedAddresses.chainlink.VRF_COORDINATOR;
    const AUTOMATION_REGISTRAR = deployedAddresses.chainlink.AUTOMATION_REGISTRAR;
    const KEY_HASH = deployedAddresses.chainlink.KEY_HASH;
    const SUBSCRIPTION_ID = deployedAddresses.chainlink.SUBSCRIPTION_ID;

    console.log(`🌐 Network: ${deployedAddresses.network} (Chain ID: ${deployedAddresses.chainId})`);
    console.log(`📋 MarketFactory: ${MARKET_FACTORY}`);
    console.log(`💰 Nostronet (NOS): ${NOSTRONET}`);

    if (!MARKET_FACTORY || !NOSTRONET) {
        throw new Error("❌ Contract addresses not found in deployed-addresses.json");
    }

    console.log("🔍 Starting contract verification...");

    try {
        // Verificar MarketFactory
        console.log("📋 Verifying MarketFactory...");
        await run("verify:verify", {
            address: MARKET_FACTORY,
            constructorArguments: [
                NOSTRONET,
                LINK_TOKEN,
                VRF_COORDINATOR,
                KEY_HASH,
                SUBSCRIPTION_ID,
                AUTOMATION_REGISTRAR,
            ],
            contract: "contracts/MarketFactory.sol:MarketFactory", // Especificar contrato exacto
        });
        console.log("✅ MarketFactory verified!");

        // Verificar Nostronet (NOS)
        console.log("💰 Verifying Nostronet (NOS)...");
        await run("verify:verify", {
            address: NOSTRONET,
            constructorArguments: ["Nostronet", "NOS", 6],
            contract: "contracts/mocks/MockERC20.sol:MockERC20", // Especificar contrato exacto
        });
        console.log("✅ Nostronet (NOS) verified!");
    } catch (error: any) {
        if (error.message.includes("Already Verified")) {
            console.log("✅ Contract already verified!");
        } else {
            console.error("❌ Verification failed:", error.message);
            console.log("\n🔧 Try manual verification:");
            console.log(`1. Go to: https://sepolia.etherscan.io/address/${MARKET_FACTORY}#code`);
            console.log("2. Click 'Contract' → 'Verify and Publish'");
            console.log("3. Use these settings:");
            console.log("   - Compiler: v0.8.19");
            console.log("   - Optimization: Yes, 200 runs");
            console.log("   - Via IR: Yes");
            console.log("4. Use flattened source from: npx hardhat flatten contracts/MarketFactory.sol");
            console.log("5. Constructor args: Use the encoded args from this verification attempt");
        }
    }
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
