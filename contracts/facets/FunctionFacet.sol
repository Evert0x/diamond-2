// SPDX-License-Identifier: MIT
pragma solidity ^0.7.1;

import "../libraries/LibDiamond.sol";

contract FunctionFacet {
    function updateFunctionMapping(bytes4[] memory extern, bytes4[] memory intern) external {
        LibDiamond.enforceIsContractOwner();
        require(extern.length == intern.length, "UNEQUAL_LENGTH");
        for (uint256 i; i < extern.length; i++) {
            LibDiamond.setFunctionMappping(extern[i], intern[i]);
        }
    }

    function getFunctionMapping(bytes4 extern) external view returns (bytes4) {
        return LibDiamond.getFunctionMapping(extern);
    }
}
