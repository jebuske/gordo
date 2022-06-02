// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IRuffle {
  function getIsBiggestBuyer(address buyer) external view returns (bool);
}
