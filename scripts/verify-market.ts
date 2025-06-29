import { run, ethers } from "hardhat";

async function main() {
    const PREDICTION_MARKET = "0x6a9ad75eac78503719ce1e6b9978d1Dd46929FCD";

    console.log("🔍 Starting PredictionMarket verification...");
    console.log("📍 Contract address:", PREDICTION_MARKET);

    try {
        // Primero intentemos leer los datos del contrato para obtener los parámetros
        console.log("📊 Reading contract data to extract constructor parameters...");

        const market = await ethers.getContractAt("PredictionMarket", PREDICTION_MARKET);

        // Leer datos del market
        const marketInfo = await market.getMarketInfo();
        const bettingToken = await market.bettingToken();
        const priceFeed = await market.priceFeed();
        const factory = await market.factory();
        const vrfCoordinator = await market.vrfCoordinator();
        const subscriptionId = await market.subscriptionId();
        const keyHash = await market.keyHash();

        console.log("📋 Market parameters found:");
        console.log("  Asset Name:", marketInfo.assetName);
        console.log("  Base Asset:", marketInfo.baseAsset);
        console.log("  Target Price:", marketInfo.targetPrice.toString());
        console.log("  Resolution Time:", new Date(Number(marketInfo.resolutionTime) * 1000).toLocaleString());
        console.log("  Betting Token:", bettingToken);
        console.log("  Price Feed:", priceFeed);
        console.log("  Factory:", factory);
        console.log("  VRF Coordinator:", vrfCoordinator);
        console.log("  Subscription ID:", subscriptionId.toString());
        console.log("  Key Hash:", keyHash);

        // Intentar obtener treasury fee (puede requerir llamada especial)
        let treasuryFee;
        try {
            const marketStruct = await market.market();
            treasuryFee = marketStruct.treasuryFee;
        } catch {
            // Si no podemos leer el struct completo, usar valor por defecto
            treasuryFee = 200; // 2% default
            console.log("⚠️  Using default treasury fee: 200 (2%)");
        }

        // Parámetros del constructor en orden
        const constructorArgs = [
            marketInfo.assetName, // string _assetName
            marketInfo.baseAsset, // string _baseAsset
            marketInfo.targetPrice, // uint256 _targetPrice
            marketInfo.resolutionTime, // uint256 _resolutionTime
            bettingToken, // address _bettingToken
            priceFeed, // address _priceFeed
            vrfCoordinator, // address _vrfCoordinator
            subscriptionId, // uint256 _subscriptionId
            keyHash, // bytes32 _keyHash
            treasuryFee, // uint16 _treasuryFee
        ];

        console.log("\n🔐 Attempting verification with extracted parameters...");

        await run("verify:verify", {
            address: PREDICTION_MARKET,
            constructorArguments: constructorArgs,
            contract: "contracts/PredictionMarket.sol:PredictionMarket",
        });

        console.log("✅ PredictionMarket verified successfully!");
        console.log(`🔗 View on Etherscan: https://sepolia.etherscan.io/address/${PREDICTION_MARKET}#code`);
    } catch (error: any) {
        if (error.message.includes("Already Verified")) {
            console.log("✅ Contract already verified!");
            console.log(`🔗 View on Etherscan: https://sepolia.etherscan.io/address/${PREDICTION_MARKET}#code`);
        } else {
            console.error("❌ Verification failed:", error.message);
            console.log("\n🔧 Try manual verification:");
            console.log(`1. Go to: https://sepolia.etherscan.io/address/${PREDICTION_MARKET}#code`);
            console.log("2. Click 'Contract' → 'Verify and Publish'");
            console.log("3. Use these settings:");
            console.log("   - Compiler: v0.8.19");
            console.log("   - Optimization: Yes, 200 runs");
            console.log("   - Via IR: Yes");
            console.log("4. Use flattened source from: npx hardhat flatten contracts/PredictionMarket.sol");
            console.log("5. Constructor args: Copy from the verification error or use extracted parameters above");
        }
    }
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
