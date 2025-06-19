// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract LoonPay is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    IERC20 public usdc;
    address[] private users;
    mapping(address => bool) private registered;
    address public trustedBackend;
    mapping(string => bool) public codeUsed;

    event Redeemed(address indexed from, uint amount);

    constructor() {
        _disableInitializers();
    }

    function initialize(address usdcAddress, address _trustedBackend) public {
        __Ownable_init(msg.sender);
        usdc = IERC20(usdcAddress);
        trustedBackend = _trustedBackend;
    }

    function redeem(
        string memory code,
        uint256 amount,
        bytes memory signature
    ) external {
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
        bool success = usdc.transfer(msg.sender, amount);
        require(success, "Transfer Failed");
    }

    // allows usdc token to be deposited to the contract
    function deposit(uint256 amount) external {
        bool success = usdc.transferFrom(msg.sender, address(this), amount);
        require(success, "USDC transfer failed");
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

    function getContractBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    receive() external payable {}
}
