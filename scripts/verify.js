require("dotenv").config();
const { run, upgrades } = require("hardhat");
const { networkConfig } = require("../helper-hardhat-config");

const PROXY_ADDRESS = "0xBC4e77eCEc95F9739E9e5103A5B213A945c64eEA";
const USDC_ADDRESS = networkConfig[network.config.chainId]["USDC_ADDRESS"];
const TRUSTED_BACKEND = process.env.TRUSTED_ADDRESS;

async function main() {
  async function verify(contractAddress, args) {
    console.log("Verifying contract...");
    try {
      await run("verify:verify", {
        address: contractAddress,
        constructorArguments: [], // Empty array for implementation
        // For proxy verification, you would use:
        // constructorArguments: args,
      });
    } catch (e) {
      if (e.message.toLowerCase().includes("already verified")) {
        console.log("Already verified");
      } else {
        console.log("Verification error:", e.message);
      }
    }
  }

  // Get implementation address
  const implementationAddress = await upgrades.erc1967.getImplementationAddress(
    PROXY_ADDRESS
  );
  console.log("Implementation address:", implementationAddress);

  // Verify implementation (no constructor args)
  console.log("Verifying implementation contract...");
  await verify(implementationAddress, []);

  // Verify proxy contract with initialization arguments
  console.log("Verifying proxy contract...");
  await run("verify:verify", {
    address: PROXY_ADDRESS,
    constructorArguments: [],
  });

  console.log("Verification complete");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
