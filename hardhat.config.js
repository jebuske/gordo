require("@nomiclabs/hardhat-waffle");
require("dotenv").config();
/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.8.4",
  networks: {
    hardhat: {
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/XO6tIRLhXQn7kMqYMJ4SEVOs8BsCUfUS`,
        blockNumber: 14884598,
      },
    },
  },
};
