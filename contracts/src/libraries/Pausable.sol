// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

abstract contract Pausable {
    struct PausableStorage {
        bool paused;
    }

    function _PausableStorage() internal pure returns (PausableStorage storage cs) {
        bytes32 position = keccak256("PausableStorage.contract.storage.v1");
        assembly {
            cs.slot := position
        }
    }

    event Paused(address account);
    event Unpaused(address account);

    function _initializePausable(bool initialPauseState) internal {
        _PausableStorage().paused = initialPauseState;
    }

    function _pause() internal {
        _PausableStorage().paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal {
        _PausableStorage().paused = false;
        emit Unpaused(msg.sender);
    }

    modifier whenPaused() {
        require(_PausableStorage().paused, "Contract is not paused");
        _;
    }

    modifier whenNotPaused() {
        require(!_PausableStorage().paused, "Contract is paused");
        _;
    }
    
    function isPaused() public view returns (bool) {
        return _PausableStorage().paused;
    }
}
