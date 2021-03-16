// SPDX-License-Identifier: MIT
pragma solidity ^0.7.1;

import "../libraries/LibDiamond.sol";

contract FunctionFacet {
    function updateFunctionMapping(bytes4[] memory from, bytes4[] memory to) external {
        LibDiamond.enforceIsContractOwner();
        require(from.length == to.length, "UNEQUAL_LENGTH");
        for (uint256 i; i < from.length; i++) {
            LibDiamond.setFunctionMappping(from[i], to[i]);
        }
    }

    function getFunctionMapping(bytes4 from) external view returns (bytes4) {
        return LibDiamond.getFunctionMapping(from);
    }
}
