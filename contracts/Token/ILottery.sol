// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface ILottery {
  function getBalance(address staker) external view returns (uint256 balance);

  function getStakers() external view returns (uint256);

  function getStaker(uint256 arrayIndex) external view returns (address);

  function getTimeStaked(address user) external view returns (uint256);
}
