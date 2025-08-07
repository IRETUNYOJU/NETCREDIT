require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: {
    version: "0.8.22",
  },
  defaultNetwork: "testnet",
  networks: {
    testnet: {
      // HashIO RPC testnet endpoint in the .env file
      url: process.env.RPC_URL,
      // Your ECDSA account private key pulled from the .env file
      accounts: [process.env.OPERATOR_KEY],
    }
  }
};