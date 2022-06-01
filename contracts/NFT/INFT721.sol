//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface INFT721 {
  function mintOnWin() external;

  function getLotteryMultiplier(uint256 n) external view returns (uint256);

  function getOnBuyMultiplier(uint256 n) external view returns (uint256);

  function getBuyAmountMultiplier(uint256 n) external view returns (uint256);

  function getTaxReducer(uint256 n) external view returns (uint256);

  function getBigSellEntries(uint256 n) external view returns (bool);

  function getFreeSell(uint256 n) external view returns (bool);
}
