// SPDX-License-Identifier: MIT
pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
/******************************************************************************/

import "../interfaces/IDiamondCut.sol";
import "../libraries/LibDiamondStorage.sol";
import "../libraries/LibDiamondCut.sol";

contract DiamondCutFacet is IDiamondCut {
    // Constants used by diamondCut
    bytes32 constant CLEAR_ADDRESS_MASK = bytes32(uint256(0xffffffffffffffffffffffff));
    bytes32 constant CLEAR_SELECTOR_MASK = bytes32(uint256(0xffffffff << 224));

    // Standard diamondCut external function
    /// @notice Add/replace/remove any number of functions and optionally execute
    ///         a function with delegatecall
    /// @param _diamondCut Contains the facet addresses and function selectors
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call, including function selector and arguments
    ///                  _calldata is executed with delegatecall on _init
    function diamondCut(
        Facet[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {
        externalCut(_diamondCut);
        emit DiamondCut(_diamondCut, _init, _calldata);
        if (_init == address(0)) {
            require(_calldata.length == 0, "DiamondCutFacet: _init is address(0) but_calldata is not empty");
        } else {
            require(_calldata.length > 0, "DiamondCutFacet: _calldata is empty but _init is not address(0)");
            if (_init != address(this)) {
                LibDiamondCut.hasContractCode(_init, "DiamondCutFacet: _init address has no code");
            }
            (bool success, bytes memory error) = _init.delegatecall(_calldata);
            if (!success) {
                if (error.length > 0) {
                    // bubble up the error
                    revert(string(error));
                } else {
                    revert("DiamondCutFacet: _init function reverted");
                }
            }
        }
    }

    // diamondCut helper function
    // This code is almost the same as the internal diamondCut function,
    // except it is using 'Facets[] calldata _diamondCut' instead of
    // 'Facet[] memory _diamondCut', and it does not issue the DiamondCut event.
    // The code is duplicated to prevent copying calldata to memory which
    // causes a Solidity error for two dimensional arrays.
    function externalCut(Facet[] calldata _diamondCut) internal {
        LibDiamondStorage.DiamondStorage storage ds = LibDiamondStorage.diamondStorage();
        require(msg.sender == ds.contractOwner, "Must own the contract.");
        bool updateLastSlot;
        uint256 originalSelectorCount = ds.selectorCount;
        // Get how many 32 byte slots are used
        uint256 selectorSlotCount = originalSelectorCount / 8;
        // Get how many function selectors are in the last 32 byte slot
        uint256 selectorsInSlot = originalSelectorCount % 8;
        bytes32 selectorSlot;
        if (selectorsInSlot > 0) {
            selectorSlot = ds.selectorSlots[selectorSlotCount];
        }
        // loop through diamond cut
        for (uint256 facetIndex; facetIndex < _diamondCut.length; facetIndex++) {
            address newFacetAddress = _diamondCut[facetIndex].facetAddress;
            // adding or replacing functions
            if (newFacetAddress != address(0)) {
                LibDiamondCut.hasContractCode(newFacetAddress, "DiamondCutFacet: facet has no code");
                // add and replace selectors
                for (uint256 selectorIndex; selectorIndex < _diamondCut[facetIndex].functionSelectors.length; selectorIndex++) {
                    bytes4 selector = _diamondCut[facetIndex].functionSelectors[selectorIndex];
                    bytes32 oldFacet = ds.facets[selector];
                    // add
                    if (oldFacet == 0) {
                        // update the last slot at then end of the function
                        updateLastSlot = true;
                        ds.facets[selector] = bytes32(bytes20(newFacetAddress)) | (bytes32(selectorsInSlot) << 64) | bytes32(selectorSlotCount);
                        // clear selector position in slot and add selector
                        selectorSlot =
                            (selectorSlot & ~(CLEAR_SELECTOR_MASK >> (selectorsInSlot * 32))) |
                            (bytes32(selector) >> (selectorsInSlot * 32));
                        selectorsInSlot++;
                        // if slot is full then write it to storage
                        if (selectorsInSlot == 8) {
                            ds.selectorSlots[selectorSlotCount] = selectorSlot;
                            selectorSlot = 0;
                            selectorsInSlot = 0;
                            selectorSlotCount++;
                        }
                    } else {
                        // replace
                        if (address(bytes20(oldFacet)) != newFacetAddress) {
                            // replace old facet address
                            ds.facets[selector] = (oldFacet & CLEAR_ADDRESS_MASK) | bytes32(bytes20(newFacetAddress));
                        }
                    }
                }
            } else {
                // remove functions
                updateLastSlot = true;
                for (uint256 selectorIndex; selectorIndex < _diamondCut[facetIndex].functionSelectors.length; selectorIndex++) {
                    bytes4 selector = _diamondCut[facetIndex].functionSelectors[selectorIndex];
                    bytes32 oldFacet = ds.facets[selector];
                    // if function does not exist then do nothing and return
                    if (oldFacet == 0) {
                        return;
                    }
                    if (selectorSlot == 0) {
                        selectorSlotCount--;
                        selectorSlot = ds.selectorSlots[selectorSlotCount];
                        selectorsInSlot = 8;
                    }
                    uint256 oldSelectorsSlotCount = uint64(uint256(oldFacet));
                    uint256 oldSelectorsInSlot = uint32(uint256(oldFacet >> 64));
                    // gets the last selector in the slot
                    bytes4 lastSelector = bytes4(selectorSlot << ((selectorsInSlot - 1) * 32));
                    if (oldSelectorsSlotCount != selectorSlotCount) {
                        bytes32 oldSelectorSlot = ds.selectorSlots[oldSelectorsSlotCount];
                        // clears the selector we are deleting and puts the last selector in its place.
                        oldSelectorSlot =
                            (oldSelectorSlot & ~(CLEAR_SELECTOR_MASK >> (oldSelectorsInSlot * 32))) |
                            (bytes32(lastSelector) >> (oldSelectorsInSlot * 32));
                        // update storage with the modified slot
                        ds.selectorSlots[oldSelectorsSlotCount] = oldSelectorSlot;
                    } else {
                        // clears the selector we are deleting and puts the last selector in its place.
                        selectorSlot =
                            (selectorSlot & ~(CLEAR_SELECTOR_MASK >> (oldSelectorsInSlot * 32))) |
                            (bytes32(lastSelector) >> (oldSelectorsInSlot * 32));
                    }
                    selectorsInSlot--;
                    if (selectorsInSlot == 0) {
                        delete ds.selectorSlots[selectorSlotCount];
                        selectorSlot = 0;
                    }
                    if (lastSelector != selector) {
                        // update last selector slot position info
                        ds.facets[lastSelector] = (oldFacet & CLEAR_ADDRESS_MASK) | bytes20(ds.facets[lastSelector]);
                    }
                    delete ds.facets[selector];
                }
            }
        }
        uint256 newSelectorCount = selectorSlotCount * 8 + selectorsInSlot;
        if (newSelectorCount != originalSelectorCount) {
            ds.selectorCount = newSelectorCount;
        }
        if (updateLastSlot && selectorsInSlot > 0) {
            ds.selectorSlots[selectorSlotCount] = selectorSlot;
        }
    }
}
