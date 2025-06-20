require("dotenv").config();
const { run, upgrades, network } = require("hardhat");

async function main() {
  const proxyAddress = "0x1b0dA50D5dc7D77Fdd18c3F3D58bb62123E22011";
  const implAddress = await upgrades.erc1967.getImplementationAddress(
    proxyAddress
  );
  console.log(`Implementation address: ${implAddress}`);

  await run("verify:verify", {
    address: implAddress,
    constructorArguments: [],
  });

  console.log("✅ Implementation contract verified.");
}

main().catch((error) => {
  console.log("failed to verify", error);
  process.exit(1);
});
