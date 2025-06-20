// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract LoonPay is Initializable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    IERC20 public usdc;
    address[] private users;
    mapping(address => bool) private registered;
    address public trustedBackend;
    mapping(string => bool) public codeUsed;

    event Redeemed(address indexed from, uint amount);
    event EmergencyWithdrawUSDC(address indexed to, uint amount);
    event EmergencyWithdrawETH(uint amount);
    event Deposited(address indexed from, address indexed to, uint amount);
    event BackendUpdated(address indexed newBackend);

    function initialize(
        address usdcAddress,
        address _trustedBackend
    ) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        usdc = IERC20(usdcAddress);
        trustedBackend = _trustedBackend;
    }

    function redeem(
        string memory code,
        uint256 amount,
        bytes memory signature
    ) external whenNotPaused {
        if (!registered[msg.sender]) {
            users.push(msg.sender);
            registered[msg.sender] = true;
        }
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
        codeUsed[code] = true;
        usdc.safeTransfer(msg.sender, amount);
        emit Redeemed(msg.sender, amount);
    }

    // allows usdc token to be deposited to the contract
    function deposit(uint256 amount) external {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, address(this), amount);
    }

    // when contract is under maintenance
    function pause() external onlyOwner {
        _pause();
    }

    // open up the contract again
    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdrawUSDC(
        address receiver,
        uint amount
    ) external onlyOwner {
        usdc.safeTransfer(receiver, amount);
        emit EmergencyWithdrawUSDC(receiver, amount);
    }

    function emergencyWithdrawETH(uint amount) external onlyOwner {
        (bool success, ) = owner().call{value: amount}("");
        require(success, "Failed to withdraw ETH");
        emit EmergencyWithdrawETH(amount);
    }

    function emergencyWithdrawAllUSDC() external onlyOwner {
        uint balance = usdc.balanceOf(address(this));
        usdc.safeTransfer(owner(), balance);
    }

    function emergencyWithdrawAllETH() external onlyOwner {
        uint balance = address(this).balance;
        (bool success, ) = owner().call{value: balance}("");
        require(success, "ETH withdraw failed");
    }

    function settrustedBackend(address _newBackend) external onlyOwner {
        trustedBackend = _newBackend;
        emit BackendUpdated(_newBackend);
    }

    function isRegistered(address user) external view returns (bool) {
        return registered[user];
    }

    function getUsers() external view returns (address[] memory) {
        return users;
    }

    function getEthSignedMessageHash(
        bytes32 hash
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
            );
    }

    function recoverSigner(
        bytes32 ethSignedHash,
        bytes memory signature
    ) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        return ecrecover(ethSignedHash, v, r, s);
    }

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

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        // '0' to '9'
        else return bytes1(uint8(b) + 0x57); // 'a' to 'f'
    }

    function getContractBalanceUSDC() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    function getContractBalanceETH() external view returns (uint) {
        return address(this).balance;
    }

    receive() external payable {}
}
