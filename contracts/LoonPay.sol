// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title LoonPay
 * @dev A contract for handling USDC token redemptions with backend signature verification
 * @notice This contract is upgradeable and includes pausing functionality for maintenance
 */

contract LoonPay is Initializable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /// @dev The USDC token contract interface
    IERC20 public usdc;

    /// @dev Array of registered user addresses
    address[] private users;

    /// @dev Mapping of registered users
    mapping(address => bool) private registered;

    /// @dev Address of the trusted backend that signs redemption requests
    address public trustedBackend;

    /// @dev Mapping of used redemption codes to prevent reuse
    mapping(string => bool) public codeUsed;

    /**
     * @dev Emitted when a user redeems USDC
     * @param from The address that redeemed the tokens
     * @param amount The amount of USDC redeemed
     */
    event Redeemed(address indexed from, uint amount);

    /**
     * @dev Emitted during emergency USDC withdrawal
     * @param to The address that received the withdrawn USDC
     * @param amount The amount of USDC withdrawn
     */
    event EmergencyWithdrawUSDC(address indexed to, uint amount);

    /**
     * @dev Emitted during emergency ETH withdrawal
     * @param amount The amount of ETH withdrawn
     */
    event EmergencyWithdrawETH(uint amount);

    /**
     * @dev Emitted when USDC is deposited to the contract
     * @param from The address that deposited the tokens
     * @param to The contract address that received the tokens
     * @param amount The amount of USDC deposited
     */
    event Deposited(address indexed from, address indexed to, uint amount);

    /**
     * @dev Emitted when the trusted backend address is updated
     * @param newBackend The new trusted backend address
     */
    event BackendUpdated(address indexed newBackend);

    /**
     * @dev Initializes the contract
     * @param usdcAddress Address of the USDC token contract
     * @param _trustedBackend Address of the trusted backend signer
     */
    function initialize(
        address usdcAddress,
        address _trustedBackend
    ) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        usdc = IERC20(usdcAddress);
        trustedBackend = _trustedBackend;
    }

    /**
     * @dev Redeems USDC tokens using a signed message from the backend
     * @param code Unique redemption code (can only be used once)
     * @param amount Amount of USDC to redeem
     * @param signature Backend signature authorizing the redemption
     * @notice The user will be registered if not already
     * @notice Can only be called when contract is not paused
     */
    function redeem(
        string memory code,
        uint256 amount,
        bytes memory signature
    ) external whenNotPaused {
        // Register user if not already registered
        if (!registered[msg.sender]) {
            users.push(msg.sender);
            registered[msg.sender] = true;
        }

        // Create message and verify signature
        string memory message = string(
            abi.encodePacked(
                "Redeem ",
                uint2str(amount),
                " to ",
                toAsciiString(msg.sender)
            )
        );
        bytes32 messageHash = getEthSignedMessageHash(
            keccak256(bytes(message))
        );
        address signer = recoverSigner(messageHash, signature);
        require(signer == trustedBackend, "Invalid backend signature");

        // Mark code as used and transfer tokens
        codeUsed[code] = true;
        usdc.safeTransfer(msg.sender, amount);
        emit Redeemed(msg.sender, amount);
    }

    /**
     * @dev Deposits USDC tokens to the contract
     * @param amount Amount of USDC to deposit
     */
    function deposit(uint256 amount) external {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, address(this), amount);
    }

    /**
     * @dev Pauses the contract (prevents redemptions)
     * @notice Can only be called by owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract (allows redemptions)
     * @notice Can only be called by owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Withdraws specified amount of USDC in emergency
     * @param receiver Address to receive the USDC
     * @param amount Amount of USDC to withdraw
     * @notice Can only be called by owner
     */
    function emergencyWithdrawUSDC(
        address receiver,
        uint amount
    ) external onlyOwner {
        usdc.safeTransfer(receiver, amount);
        emit EmergencyWithdrawUSDC(receiver, amount);
    }

    /**
     * @dev Withdraws specified amount of ETH in emergency
     * @param amount Amount of ETH to withdraw
     * @notice Can only be called by owner
     */
    function emergencyWithdrawETH(uint amount) external onlyOwner {
        (bool success, ) = owner().call{value: amount}("");
        require(success, "Failed to withdraw ETH");
        emit EmergencyWithdrawETH(amount);
    }

    /**
     * @dev Withdraws all USDC from contract in emergency
     * @notice Can only be called by owner
     */
    function emergencyWithdrawAllUSDC() external onlyOwner {
        uint balance = usdc.balanceOf(address(this));
        usdc.safeTransfer(owner(), balance);
    }

    /**
     * @dev Withdraws all ETH from contract in emergency
     * @notice Can only be called by owner
     */
    function emergencyWithdrawAllETH() external onlyOwner {
        uint balance = address(this).balance;
        (bool success, ) = owner().call{value: balance}("");
        require(success, "ETH withdraw failed");
    }

    /**
     * @dev Updates the trusted backend address
     * @param _newBackend New trusted backend address
     * @notice Can only be called by owner
     */
    function settrustedBackend(address _newBackend) external onlyOwner {
        trustedBackend = _newBackend;
        emit BackendUpdated(_newBackend);
    }

    /**
     * @dev Checks if an address is registered
     * @param user Address to check
     * @return bool True if address is registered
     */
    function isRegistered(address user) external view returns (bool) {
        return registered[user];
    }

    /**
     * @dev Returns array of all registered users
     * @return address[] Array of user addresses
     */
    function getUsers() external view returns (address[] memory) {
        return users;
    }

    /**
     * @dev Generates Ethereum signed message hash
     * @param hash The original message hash
     * @return bytes32 The Ethereum signed message hash
     */
    function getEthSignedMessageHash(
        bytes32 hash
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
            );
    }

    /**
     * @dev Recovers the signer address from signature
     * @param ethSignedHash The signed message hash
     * @param signature The signature bytes
     * @return address The recovered signer address
     */
    function recoverSigner(
        bytes32 ethSignedHash,
        bytes memory signature
    ) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        return ecrecover(ethSignedHash, v, r, s);
    }

    /**
     * @dev Splits signature into r, s, v components
     * @param sig The signature bytes
     * @return r First 32 bytes of signature
     * @return s Next 32 bytes of signature
     * @return v Final byte of signature
     */
    function splitSignature(
        bytes memory sig
    ) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    /**
     * @dev Converts uint to string
     * @param _i The uint to convert
     * @return string The string representation of the uint
     */
    function uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) return "0";
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + (j % 10)));
            j /= 10;
        }
        return string(bstr);
    }

    /**
     * @dev Converts address to ASCII string
     * @param x The address to convert
     * @return string The ASCII string representation of the address
     */
    function toAsciiString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) % 16);
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(abi.encodePacked("0x", s));
    }

    /**
     * @dev Converts byte to ASCII character
     * @param b The byte to convert
     * @return c The ASCII character
     */
    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        // '0' to '9'
        else return bytes1(uint8(b) + 0x57); // 'a' to 'f'
    }

    /**
     * @dev Gets contract's USDC balance
     * @return uint256 The USDC balance
     */
    function getContractBalanceUSDC() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    /**
     * @dev Gets contract's ETH balance
     * @return uint The ETH balance
     */
    function getContractBalanceETH() external view returns (uint) {
        return address(this).balance;
    }

    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {}
}
