// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// @param ETH_NODE The node hash of "eth"
bytes32 constant ETH_NODE = 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;
// @param FACET_ETH_NODE The node hash of "base.eth"
bytes32 constant FACET_ETH_NODE = 0x989e4539d443b3938e18a18fedbb006a952f3b42bb47004fe1bfd15da58728e1;
// @param REVERSE_NODE The node hash of "reverse"
bytes32 constant REVERSE_NODE = 0xa097f6721ce401e757d1223a763fef49b8b5f90bb18567ddb86fd205dff71d34;
// @param ADDR_REVERSE_NODE The node hash of "addr.reverse"
bytes32 constant ADDR_REVERSE_NODE = 0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;
// @param FACET_REVERSE_NODE The ENSIP-19 compliant base-specific reverse node hash of "80002105.reverse"
bytes32 constant FACET_REVERSE_NODE = 0xcbfcd9beb58ba8ca96cc44369a8772bb59e9e66c34598893dc9a17c8a7a24880;
// @param GRACE_PERIOD the grace period for expired names
uint256 constant GRACE_PERIOD = 90 days;
// @param FACET_ETH_NAME The dnsName of "base.eth" returned by NameEncoder.dnsEncode("base.eth")
bytes constant FACET_ETH_NAME = hex"0566616365740365746800";
