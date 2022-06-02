//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface INFT721 {
  function mintOnWin() external;

  function getLotteryMultiplier(uint256 n) external view returns (uint256);

  function getOnBuyMultiplier(uint256 n) external view returns (uint256);

  function getFreeTokens(uint256 n) external view returns (uint256);

  function getTaxReducer(uint256 n) external view returns (uint256);

  function getBigSellEntries(uint256 n) external view returns (bool);

  function getFreeSell(uint256 n) external view returns (bool);

  function burn(uint256 tokenId) external;

  function ownerOf(uint256 tokenId) external view returns (address owner);

  function approve(address to, uint256 tokenId) external;

  function safeTransferFrom(
    address from,
    address to,
    uint256 tokenId
  ) external;

  function balanceOf(address owner) external view returns (uint256 balance);

  function tokenOfOwnerByIndex(address owner, uint256 index)
    external
    view
    returns (uint256);
}
